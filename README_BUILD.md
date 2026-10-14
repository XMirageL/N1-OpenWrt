# N1 OpenWrt 固件编译指南 (WSL)

本指南帮助你在 Windows WSL 环境中编译 N1 OpenWrt 固件。

## 前置要求

1. **Windows 10/11** 并已安装 WSL2（推荐使用 Ubuntu 22.04 或 24.04）
2. **至少 30GB 可用磁盘空间**
3. **至少 8GB 内存**（推荐 16GB）
4. **稳定的网络连接**（需要下载大量软件包）

## 快速开始

### 1. 克隆本项目

```bash
cd ~
git clone https://github.com/nantayo/N1-OpenWrt.git
cd N1-OpenWrt
```

### 2. 运行编译脚本

```bash
./build_n1_openwrt.sh
```

脚本会自动完成所有编译步骤，整个过程大约需要 1-3 小时（取决于你的硬件配置）。

## 自定义配置

编译脚本 `build_n1_openwrt.sh` 顶部有详细的配置选项，你可以根据需要修改：

### 基础配置

```bash
# 源码仓库配置
REPO_URL="https://github.com/immortalwrt/immortalwrt"
REPO_BRANCH="openwrt-25.12"

# 工作目录（可以修改为其他路径）
WORK_DIR="$HOME/openwrt_build"

# 编译线程数（根据你的CPU核心数调整）
COMPILE_THREADS=$(($(nproc) + 1))
```

### 固件配置

```bash
# 固件打包配置
OPENWRT_BOARD="s905d"           # N1 芯片型号
KERNEL_VERSION="6.12.y"         # 内核版本
OPENWRT_SIZE="256/1024"         # 固件分区大小 (boot/rootfs MB)
BUILDER_NAME="nantayo"          # 构建者名称（可修改为你的名字）
```

### 开关选项

```bash
# 是否清理旧的工作目录（1=是，0=否）
CLEAN_OLD_BUILD=0

# 是否跳过依赖安装（如果已经安装过可以设为1）
SKIP_DEPENDENCIES=0

# 是否启用详细编译输出（1=是，0=否，调试时建议启用）
VERBOSE_BUILD=0
```

## 可选软件包

脚本默认会安装以下软件包，你可以通过注释相应代码来禁用：

### luci-app-amlogic（必需）
- N1 系统管理工具
- 提供系统更新、文件传输、CPU 调频等功能
- **不建议禁用**

### luci-app-passwall（可选）
传统的代理工具，简单易用，内存占用较低。

**如不需要，注释掉以下行：**
```bash
# 在 add_custom_packages() 函数中
# git clone https://github.com/Openwrt-Passwall/openwrt-passwall --depth=1 clone/passwall

# 在 adjust_packages() 函数中
# if [ -d "clone/passwall" ]; then
#     cp -rf clone/passwall/luci-app-passwall feeds/luci/applications/
# fi
```

同时修改 `armsr/armv8/N1/.config` 文件，注释掉：
```
# CONFIG_PACKAGE_luci-app-passwall=y
```

### luci-app-daed（可选）
基于 eBPF 的现代代理工具，直连性能优异，但内存占用较大。

**如不需要，注释掉以下行：**
```bash
# 在 add_custom_packages() 函数中
# git clone https://github.com/QiuSimons/luci-app-daed --single-branch --depth=1 clone/daed

# 在 adjust_packages() 函数中
# if [ -d "clone/daed" ]; then
#     cp -rf clone/daed/luci-app-daed feeds/luci/applications/
# fi
```

同时修改 `armsr/armv8/N1/.config` 文件，注释掉：
```
# CONFIG_PACKAGE_luci-app-daed=y
# CONFIG_BPF_TOOLCHAIN_HOST=y
# CONFIG_DEVEL=y
# CONFIG_KERNEL_BPF_EVENTS=y
# CONFIG_KERNEL_DEBUG_INFO_BTF=y
# CONFIG_KERNEL_DEBUG_INFO_REDUCED=n
# CONFIG_KERNEL_XDP_SOCKETS=y
```

### luci-app-podman（可选）
容器管理工具，支持运行 Docker 容器。

**如不需要，注释掉以下行：**
```bash
# 在 add_custom_packages() 函数中
# git clone https://github.com/Zerogiven-OpenWRT-Packages/luci-app-podman --single-branch --depth=1 feeds/luci/applications/luci-app-podman
```

同时修改 `armsr/armv8/N1/.config` 文件，注释掉：
```
# CONFIG_PACKAGE_luci-app-podman=y
# CONFIG_PACKAGE_podman=y
```

### luci-app-samba4（可选）
文件共享服务，可以在局域网中共享 N1 的存储。

修改 `armsr/armv8/N1/.config` 文件，注释掉：
```
# CONFIG_PACKAGE_luci-app-samba4=y
```

## 编译流程说明

脚本会按照以下步骤执行：

1. **检查环境** - 验证 WSL 环境和磁盘空间
2. **安装依赖** - 安装编译所需的系统包
3. **准备工作目录** - 创建编译工作目录
4. **克隆源码** - 下载 ImmortalWrt 源码
5. **添加自定义包** - 克隆第三方软件包
6. **调整配置** - 配置软件包和编译参数
7. **更新 Feeds** - 更新和安装软件源
8. **加载配置** - 应用自定义配置文件
9. **下载依赖** - 下载编译所需的依赖包
10. **编译固件** - 编译 OpenWrt（最耗时）
11. **打包固件** - 打包成 N1 可用的固件格式
12. **完成** - 显示固件位置和默认配置

## 编译输出

编译完成后，固件会保存在：
```
$HOME/openwrt_build/amlogic-s9xxx-openwrt/out/
```

固件文件格式：
- `*.img.gz` - 压缩的固件镜像

## 固件刷写

1. 解压固件：`gunzip *.img.gz`
2. 使用工具（如 Rufus、balenaEtcher）将 `.img` 文件写入 U 盘
3. 将 U 盘插入 N1，从 U 盘启动
4. 访问 `http://192.168.2.2` 登录系统（用户名：root，密码：password）
5. 使用 luci-app-amlogic 将系统安装到 eMMC

## 默认配置

- **IP 地址**: 192.168.2.2
- **子网掩码**: 255.255.255.0
- **网关**: 192.168.2.1
- **用户名**: root
- **密码**: password
- **SSH**: 已启用
- **Web 管理**: http://192.168.2.2

## 故障排查

### 编译失败

1. **检查磁盘空间**：确保至少有 30GB 可用空间
2. **检查内存**：编译过程会消耗大量内存
3. **网络问题**：某些软件包可能下载失败，重新运行脚本即可
4. **启用详细输出**：设置 `VERBOSE_BUILD=1` 查看详细错误信息

### 依赖安装失败

如果依赖安装失败，可以手动安装：
```bash
sudo apt-get update
sudo apt-get install -y build-essential clang flex bison g++ gawk gcc-multilib gettext git libncurses5-dev libssl-dev python3-distutils rsync unzip zlib1g-dev file wget
```

### 打包失败

检查是否生成了 rootfs.tar.gz：
```bash
find $HOME/openwrt_build/openwrt/bin/targets/armsr/armv8/ -name "*rootfs.tar.gz"
```

## 增量编译

如果需要修改配置后重新编译，不需要从头开始：

1. 设置 `SKIP_DEPENDENCIES=1` 跳过依赖安装
2. 设置 `CLEAN_OLD_BUILD=0` 保留已下载的源码
3. 修改 `.config` 或软件包后重新运行脚本

## 自定义网络配置

编辑 `armsr/armv8/N1/files/etc/config/network` 修改默认 IP：

```
config interface 'lan'
	option proto 'static'
	option device 'eth0'
	option ipaddr '192.168.2.2/24'    # 修改这里
	option gateway '192.168.2.1'      # 修改这里
	option multipath 'off'
	option delegate '0'
```

## 技术支持

- **项目地址**: https://github.com/nantayo/N1-OpenWrt
- **ImmortalWrt**: https://github.com/immortalwrt/immortalwrt
- **打包脚本**: https://github.com/ophub/amlogic-s9xxx-openwrt
- **恩山论坛**: https://www.right.com.cn/forum/

## 许可证

本项目基于 ImmortalWrt 和相关开源项目，遵循相应的开源许可证。

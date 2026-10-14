#!/bin/bash
#===============================================================================
# N1 OpenWrt 旁路由专用固件编译脚本 (WSL 修正优化版)
# 基于 ImmortalWrt 源码
#===============================================================================

set -e  # 遇到错误立即退出

# 【关键修复 1】必须在任何 cd 命令之前锁定脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 【关键修复 2】屏蔽 WSL 中的 Windows PATH，避免带空格路径导致编译出错
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

#===============================================================================
# 配置区域 - 根据需要修改
#===============================================================================

REPO_URL="https://github.com/immortalwrt/immortalwrt"
# 注意：请确认 ImmortalWrt 仓库中已存在 openwrt-25.12 分支，若尚未创建请用 openwrt-24.10 或 master
REPO_BRANCH="openwrt-24.10"
export TZ="Asia/Shanghai"

WORK_DIR="$HOME/openwrt_build"
COMPILE_THREADS=$(($(nproc) + 1))

# 固件打包配置 (ophub)
OPENWRT_BOARD="s905d"           # N1 芯片型号
KERNEL_VERSION="6.12.y"         # 推荐使用 6.12 LTS 内核
OPENWRT_SIZE="256/1024"         # 固件分区大小 (boot/rootfs MB)
BUILDER_NAME="linji"            # 构建者名称

CLEAN_OLD_BUILD=0
SKIP_DEPENDENCIES=0
VERBOSE_BUILD=0

# 代理插件选择开关 (1=启用, 0=不启用)
ENABLE_PASSWALL=1
ENABLE_DAED=0

#===============================================================================
# 颜色输出定义
#===============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

#===============================================================================
# 步骤 1: 检查环境
#===============================================================================
check_environment() {
    log_step "检查运行环境..."
    if [ "$(id -u)" -eq 0 ]; then
        log_error "请勿使用 root 用户直接运行此脚本！"
        exit 1
    fi

    if ! grep -qi microsoft /proc/version; then
        log_warn "未检测到 WSL 环境，按普通 Linux 环境继续..."
    else
        log_info "检测到 WSL 环境，已自动清理 Windows PATH 污染"
    fi

    available_space=$(df -BG "$HOME" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_space" -lt 30 ]; then
        log_error "磁盘空间不足！至少需要 30GB，当前可用: ${available_space}GB"
        exit 1
    fi
    log_info "磁盘空间充足: ${available_space}GB"
}

#===============================================================================
# 步骤 2: 安装编译依赖 (兼容 Ubuntu 22.04 / 24.04)
#===============================================================================
install_dependencies() {
    if [ "$SKIP_DEPENDENCIES" -eq 1 ]; then
        log_info "跳过依赖安装（SKIP_DEPENDENCIES=1）"
        return
    fi

    log_step "更新软件包列表并安装编译依赖..."
    sudo apt-get update -qq

    sudo apt-get install -y \
        ack antlr3 asciidoc autoconf automake autopoint binutils bison \
        build-essential bzip2 ccache clang cmake cpio curl device-tree-compiler \
        dwarves ecj fastjar flex gawk gettext gcc-multilib g++-multilib git \
        gperf haveged help2man intltool libc6-dev-i386 libelf-dev libfuse-dev \
        libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev \
        libncurses-dev libpython3-dev libreadline-dev libssl-dev libtool \
        libyaml-dev libz-dev lld llvm lrzsz msmtp nano ninja-build p7zip \
        p7zip-full patch pkgconf python3 python3-pip python3-ply \
        python3-setuptools qemu-utils rsync scons squashfs-tools subversion \
        swig texinfo uglifyjs upx-ucl unzip vim wget xmlto xxd zlib1g-dev

    sudo apt-get autoremove --purge -y
    sudo apt-get clean
    log_info "依赖安装完成"
}

#===============================================================================
# 步骤 3 & 4: 准备工作目录与克隆源码
#===============================================================================
prepare_and_clone() {
    log_step "准备工作目录与源码: $WORK_DIR"
    if [ -d "$WORK_DIR" ] && [ "$CLEAN_OLD_BUILD" -eq 1 ]; then
        log_warn "清理旧的工作目录..."
        rm -rf "$WORK_DIR"
    fi
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"

    if [ -d "$WORK_DIR/openwrt" ]; then
        log_info "源码目录已存在，重置并更新代码..."
        cd "$WORK_DIR/openwrt"
        git reset --hard
        git clean -fd
        git pull
    else
        git clone "$REPO_URL" -b "$REPO_BRANCH" --single-branch --depth=1 openwrt
        log_info "源码克隆完成"
    fi
}

#===============================================================================
# 步骤 5: 更新 Feeds 并注入第三方包与优化参数
#===============================================================================
setup_feeds_and_packages() {
    log_step "更新 Feeds 并配置第三方软件包..."
    cd "$WORK_DIR/openwrt"

    # 1. 清理旧的 feeds 修改与缓存，再拉取最新官方 feeds
    ./scripts/feeds clean
    ./scripts/feeds update -a

    # 2. 清理临时目录并拉取第三方源码到 package/custom
    rm -rf package/custom
    mkdir -p package/custom

    # --- luci-app-amlogic (N1 晶晨刷机/内核更新工具，必需) ---
    log_info "添加 luci-app-amlogic..."
    git clone https://github.com/ophub/luci-app-amlogic --single-branch --depth=1 package/custom/amlogic

    # --- Passwall 及其核心依赖包 ---
    if [ "$ENABLE_PASSWALL" -eq 1 ]; then
        log_info "清理官方 feeds 中可能冲突的旧版核心包并添加 Passwall..."
        rm -rf feeds/luci/applications/luci-app-passwall
        rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}
        git clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages --single-branch --depth=1 package/custom/passwall-packages
        git clone https://github.com/Openwrt-Passwall/openwrt-passwall --single-branch --depth=1 package/custom/passwall
    fi

    # --- daed ---
    if [ "$ENABLE_DAED" -eq 1 ]; then
        log_info "添加 luci-app-daed..."
        rm -rf feeds/luci/applications/luci-app-daed
        rm -rf feeds/packages/net/daed
        git clone https://github.com/QiuSimons/luci-app-daed --single-branch --depth=1 package/custom/daed
    fi

    # --- Argon 主题 (美观现代化的 Web 界面主题) ---
    log_info "添加 Argon 主题..."
    rm -rf feeds/luci/themes/luci-theme-argon
    rm -rf feeds/luci/applications/luci-app-argon-config
    git clone https://github.com/jerrykuku/luci-theme-argon --single-branch --depth=1 package/custom/argon
    git clone https://github.com/jerrykuku/luci-app-argon-config --single-branch --depth=1 package/custom/argon-config

    # 3. 调整源码编译参数
    sed -i '/luci-app-attendedsysupgrade/d' feeds/luci/collections/luci/Makefile

    # 启用 S905D (ARMv8-A) Golang 硬件加密指令集加速
    if [ -f "feeds/packages/lang/golang/golang-values.mk" ]; then
        sed -i 's/GO_ARM64:=v8\.0$/GO_ARM64:=v8.0,crypto/' feeds/packages/lang/golang/golang-values.mk
        log_info "已启用 Golang ARM64 Crypto 硬件指令集优化"
    fi

    # 4. 清理包索引缓存并安装所有 feeds 包 (-f 优先使用自定义包)
    rm -rf tmp
    ./scripts/feeds install -a -f
    log_info "Feeds 与自定义软件包配置完成"
}

#===============================================================================
# 步骤 6: 加载自定义配置
#===============================================================================
load_custom_config() {
    log_step "加载自定义配置..."
    cd "$WORK_DIR/openwrt"

    rm -rf files .config

    if [ -d "$SCRIPT_DIR/armsr/armv8/N1/files" ]; then
        cp -r "$SCRIPT_DIR/armsr/armv8/N1/files" .
        chmod -R 755 files
        log_info "已复制自定义 files 目录"
    else
        log_warn "未找到自定义 files 目录，将使用源码默认设置"
    fi

    if [ -f "$SCRIPT_DIR/armsr/armv8/N1/.config" ]; then
        cp "$SCRIPT_DIR/armsr/armv8/N1/.config" .
        log_info "已复制 .config 文件"
    else
        log_error "未找到 .config 文件: $SCRIPT_DIR/armsr/armv8/N1/.config"
        exit 1
    fi
}

#===============================================================================
# 步骤 7 & 8: 下载依赖与编译固件
#===============================================================================
build_firmware() {
    cd "$WORK_DIR/openwrt"

    log_step "生成完整配置并下载源码包..."
    make defconfig
    make download -j$(( $(nproc) * 2 ))
    sed -i 's/GOTOOLCHAIN=local/GOTOOLCHAIN=auto/g' feeds/packages/lang/golang/golang-package.mk

    log_step "开始编译固件..."
    if [ "$VERBOSE_BUILD" -eq 1 ]; then
        make -j1 V=s
    else
        make -j${COMPILE_THREADS} || make -j1 V=s
    fi
    log_info "OpenWrt Rootfs 编译完成"
}

#===============================================================================
# 步骤 9: 打包 N1 固件
#===============================================================================
package_firmware() {
    log_step "打包 N1 镜像固件..."
    cd "$WORK_DIR"

    ROOTFS_FILE=$(find "$WORK_DIR/openwrt/bin/targets/armsr/armv8/" -name "*rootfs.tar.gz" | head -n 1)
    if [ -z "$ROOTFS_FILE" ]; then
        log_error "未找到 *rootfs.tar.gz 文件，请检查 .config 中是否包含 CONFIG_TARGET_ROOTFS_TARGZ=y"
        exit 1
    fi
    log_info "找到 Rootfs 文件: $ROOTFS_FILE"

    if [ ! -d "amlogic-s9xxx-openwrt" ]; then
        git clone https://github.com/ophub/amlogic-s9xxx-openwrt --depth=1
    else
        cd amlogic-s9xxx-openwrt && git pull && cd "$WORK_DIR"
    fi

    # 将 rootfs 放入 ophub 指定的输入目录
    mkdir -p amlogic-s9xxx-openwrt/openwrt-armvirt
    rm -f amlogic-s9xxx-openwrt/openwrt-armvirt/*
    cp -f "$ROOTFS_FILE" amlogic-s9xxx-openwrt/openwrt-armvirt/

    cd amlogic-s9xxx-openwrt
    sudo ./make -b "$OPENWRT_BOARD" -k "$KERNEL_VERSION" -s "$OPENWRT_SIZE" -n "$BUILDER_NAME"

    OUTPUT_DIR="$WORK_DIR/amlogic-s9xxx-openwrt/out"
    if [ -d "$OUTPUT_DIR" ]; then
        log_info "固件打包成功！输出目录: $OUTPUT_DIR"
        ls -lh "$OUTPUT_DIR"/*.img* 2>/dev/null || log_warn "未找到生成的 .img 文件"
    else
        log_error "打包失败，未找到输出目录"
        exit 1
    fi
}

main() {
    check_environment
    install_dependencies
    prepare_and_clone
    setup_feeds_and_packages
    load_custom_config
    build_firmware
    package_firmware
}

main
#!/bin/bash

# Clone packages
git clone https://github.com/ophub/luci-app-amlogic --single-branch --depth=1 clone/amlogic
git clone https://github.com/Openwrt-Passwall/openwrt-passwall --depth=1 clone/passwall

# Clone Argon theme
git clone https://github.com/jerrykuku/luci-theme-argon --single-branch --depth=1 clone/argon
git clone https://github.com/jerrykuku/luci-app-argon-config --single-branch --depth=1 clone/argon-config

# Adjust packages
rm -rf feeds/luci/applications/luci-app-daed feeds/luci/applications/luci-app-passwall
rm -rf feeds/luci/themes/luci-theme-argon feeds/luci/applications/luci-app-argon-config
cp -rf clone/amlogic/luci-app-amlogic clone/passwall/luci-app-passwall feeds/luci/applications/
cp -rf clone/argon feeds/luci/themes/luci-theme-argon
cp -rf clone/argon-config feeds/luci/applications/luci-app-argon-config
sed -i '/luci-app-attendedsysupgrade/d' feeds/luci/collections/luci/Makefile
sed -i 's/GO_ARM64:=v8\.0$/GO_ARM64:=v8.0,crypto/' feeds/packages/lang/golang/golang-values.mk

# Clean packages
rm -rf clone
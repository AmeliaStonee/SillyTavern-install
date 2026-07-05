#!/data/data/com/termux/files/usr/bin/bash

export PATH="/data/data/com/termux/files/usr/bin:$PATH"

MANAGER_VERSION="1.0"
ST_DIR_NAME="SillyTavern"
ST_DIR="${HOME}/${ST_DIR_NAME}"
ST_DATA_USER_SUBPATH="data/default-user"
SCRIPT_INSTALL_DIR="${HOME}/.st-manager"
SCRIPT_PATH="${SCRIPT_INSTALL_DIR}/st-manager.sh"
CONFIG_FILE="${SCRIPT_INSTALL_DIR}/config.conf"
LOG_FILE="${SCRIPT_INSTALL_DIR}/backup.log"
CACHE_FILE="${SCRIPT_INSTALL_DIR}/versions.cache"
CACHE_DURATION=3600

# --- ClewdR 代理 ---
CLEWDR_REPO="Xerxes-2/clewdr"
CLEWDR_DIR="${HOME}/clewdr"
CLEWDR_BIN="${CLEWDR_DIR}/clewdr"
CLEWDR_CONFIG="${CLEWDR_DIR}/clewdr.toml"

SCRIPT_URL="https://raw.githubusercontent.com/AmeliaStonee/SillyTavern-install/main/st-manager.sh"

C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "${LOG_FILE}"; }
ensure_dirs() { mkdir -p "${SCRIPT_INSTALL_DIR}"; }

# --- 网络下载封装：优先 curl，回退 wget ---
# Termux 默认可能只装了其中一个（甚至都没装）。脚本原先只用 wget，
# 一旦缺失就会 "wget: command not found"，导致版本检测与自更新全部失败。
http_get() {  # 下载到标准输出
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 8 "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- --timeout=8 "$url"
    else
        return 127
    fi
}
http_download() {  # 下载到文件：http_download <url> <输出路径>
    local url="$1" out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 20 -o "$out" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$out" "$url"
    else
        return 127
    fi
}

# --- 从 package.json 文本中解析 version 字段 ---
# SillyTavern 前端展示的版本号就是 package.json 里的 "version"，
# 本地版本检测也读取同一字段，因此用它来对比最为一致。
parse_pkg_version() {
    echo "$1" | grep '"version":' | head -n1 | sed 's/.*: *"\([^"]*\)".*/\1/'
}

# --- 使用缓存获取版本 ---
# 说明：release / staging 版本均直接读取对应分支的 package.json（raw 源）。
# 早期版本用 api.github.com 的 releases/latest 获取 release 版本，但未认证的
# GitHub API 每小时仅限 60 次请求，Termux 手机网络共享运营商出口 IP，极易触发
# 速率限制导致“查询失败(速率限制?)”。raw.githubusercontent.com 无此限制，更可靠。
fetch_remote_versions() {
    local needs_fetch=false
    if [ ! -f "${CACHE_FILE}" ]; then
        needs_fetch=true
    else
        local cache_time=$(date -r "${CACHE_FILE}" +%s)
        local current_time=$(date +%s)
        if (( current_time - cache_time > CACHE_DURATION )); then
            needs_fetch=true
        fi
    fi

    if $needs_fetch; then
        echo -e "${C_YELLOW}正在联网查询最新版本...${C_RESET}"
        # Release 版本：读取 release 分支（SillyTavern 的稳定分支，即默认分支）的 package.json
        local release_url="https://raw.githubusercontent.com/SillyTavern/SillyTavern/release/package.json"
        local release_json=$(http_get "$release_url")
        if [ $? -eq 0 ] && [ -n "$release_json" ]; then
            RELEASE_VER=$(parse_pkg_version "$release_json")
            [ -z "$RELEASE_VER" ] && RELEASE_VER="解析失败"
        else
            RELEASE_VER="查询失败"
        fi
        # Staging 版本：读取 staging 分支（开发分支）的 package.json
        local staging_url="https://raw.githubusercontent.com/SillyTavern/SillyTavern/staging/package.json"
        local staging_json=$(http_get "$staging_url")
        if [ $? -eq 0 ] && [ -n "$staging_json" ]; then
            STAGING_VER=$(parse_pkg_version "$staging_json")
            [ -z "$STAGING_VER" ] && STAGING_VER="解析失败"
        else
            STAGING_VER="查询失败"
        fi
        echo "RELEASE_VER='${RELEASE_VER}'" > "${CACHE_FILE}"
        echo "STAGING_VER='${STAGING_VER}'" >> "${CACHE_FILE}"
    else
        source "${CACHE_FILE}"
    fi
}

# --- SillyTavern核心功能 ---
install_sillytavern() {
    echo -e "${C_CYAN}=== 开始安装 SillyTavern ===${C_RESET}"
    pkg update -y && pkg upgrade -y
    pkg install git nodejs esbuild cronie zip unzip curl wget -y
    read -p "您想安装哪个分支？[1] release (稳定版, 默认) [2] staging (开发版): " choice
    choice=${choice:-1}
    if [[ "$choice" == "1" ]]; then git clone https://github.com/SillyTavern/SillyTavern "${ST_DIR}"; else git clone -b staging https://github.com/SillyTavern/SillyTavern "${ST_DIR}"; fi
    if [ ! -d "${ST_DIR}" ]; then echo -e "${C_RED}克隆失败，请检查网络。${C_RESET}"; exit 1; fi
    cd "${ST_DIR}" || exit
    npm install
    if [ -f "start.sh" ]; then echo -e "${C_GREEN}SillyTavern 安装成功！建议配置备份。${C_RESET}"; sleep 2; setup_backup; else echo -e "${C_RED}安装失败。${C_RESET}"; exit 1; fi
}

start_sillytavern() {
    echo -e "${C_CYAN}=== 启动 SillyTavern ===${C_RESET}"
    if [ -f "$CONFIG_FILE" ]; then
        if ! pgrep -f "crond" > /dev/null; then
            echo -e "${C_YELLOW}备份服务未运行，正在自动启动...${C_RESET}"; crond
            echo -e "${C_GREEN}备份服务已启动。${C_RESET}"
        else
             echo -e "${C_GREEN}备份服务正常运行中。${C_RESET}"
        fi
    fi
    if clewdr_is_installed; then
        read -p "$(echo -e "${C_YELLOW}检测到已安装 ClewdR，是否先在后台启动 ClewdR？[Y/n]: ${C_RESET}")" st_clewdr
        st_clewdr=${st_clewdr:-Y}
        if [[ "$st_clewdr" =~ ^[Yy]$ ]]; then start_clewdr_background; sleep 1; fi
    fi
    cd "${ST_DIR}" || { echo -e "${C_RED}错误: 无法进入目录 ${ST_DIR}${C_RESET}"; exit 1; }
    bash start.sh
}

update_sillytavern() {
    echo -e "${C_CYAN}=== 更新 SillyTavern ===${C_RESET}"; cd "${ST_DIR}" || exit
    echo -e "1. 拉取当前分支更新\n2. 切换到其他分支"
    read -p "请输入选项 (默认: 0 返回): " choice; choice=${choice:-0}
    case $choice in
        1) git pull && npm install && echo -e "${C_GREEN}更新完成！${C_RESET}";;
        2) echo "切换到: [1] release [2] staging"; read -p "请输入选项: " s_choice
           case $s_choice in
               1) git switch release && git pull && npm install && echo -e "${C_GREEN}已切换到 release。${C_RESET}";;
               2) git switch staging && git pull && npm install && echo -e "${C_GREEN}已切换到 staging。${C_RESET}";;
               *) echo -e "${C_RED}无效。${C_RESET}";;
           esac;;
        0) return;;
        *) echo -e "${C_RED}无效。${C_RESET}";;
    esac
    read -p "按回车返回..."
}

# --- 备份功能 ---
load_backup_config() { if [ -f "${CONFIG_FILE}" ]; then source "${CONFIG_FILE}"; else BACKUP_DIR=""; BACKUP_DAYS=""; BACKUP_TIME=""; fi; }
run_backup() { load_backup_config; if [ -z "${BACKUP_DIR}" ]; then log "备份失败：未配置"; return 1; fi; local data_dir="${ST_DIR}/${ST_DATA_USER_SUBPATH}"; if [ ! -d "${data_dir}" ]; then log "备份失败：找不到数据目录"; return 1; fi; mkdir -p "${BACKUP_DIR}"; local timestamp=$(date +%Y%m%d-%H%M); local filename="SillyTavern-Backup-${timestamp}.zip"; log "开始备份到 ${filename}"; local parent_dir=$(dirname "${data_dir}"); local user_data_folder=$(basename "${data_dir}"); pushd "${parent_dir}" > /dev/null; zip -r "${BACKUP_DIR}/${filename}" "${user_data_folder}"; popd > /dev/null; log "清理旧备份..."; find "${BACKUP_DIR}" -name "SillyTavern-Backup-*.zip" -mtime +"${BACKUP_DAYS}" -exec rm {} \;; log "清理完成"; return 0; }
setup_backup() { echo -e "${C_CYAN}=== 配置自动备份 ===${C_RESET}"; local default_backup_dir="${HOME}/SillyTavern-Backups"; read -p "备份目录 (默认: ${default_backup_dir}): " backup_dir; BACKUP_DIR=${backup_dir:-${default_backup_dir}}; read -p "保留天数 (默认: 7): " backup_days; BACKUP_DAYS=${backup_days:-7}; local hour minute; while true; do read -p "设置备份小时 (0-23): " hour; if [[ "$hour" =~ ^[0-9]+$ ]] && [ "$hour" -ge 0 ] && [ "$hour" -le 23 ]; then break; else echo -e "${C_RED}输入无效。${C_RESET}"; fi; done; while true; do read -p "设置备份分钟 (0-59): " minute; if [[ "$minute" =~ ^[0-9]+$ ]] && [ "$minute" -ge 0 ] && [ "$minute" -le 59 ]; then break; else echo -e "${C_RED}输入无效。${C_RESET}"; fi; done; BACKUP_TIME=$(printf "%02d:%02d" "$hour" "$minute"); mkdir -p "${SCRIPT_INSTALL_DIR}"; echo "BACKUP_DIR=\"${BACKUP_DIR}\"" > "${CONFIG_FILE}"; echo "BACKUP_DAYS=\"${BACKUP_DAYS}\"" >> "${CONFIG_FILE}"; echo "BACKUP_TIME=\"${BACKUP_TIME}\"" >> "${CONFIG_FILE}"; echo -e "${C_GREEN}配置已保存。${C_RESET}"; install_cron_job; }
install_cron_job() { load_backup_config; if [ -z "${BACKUP_TIME}" ]; then return; fi; local minute=$(echo "$BACKUP_TIME" | cut -d: -f2); local hour=$(echo "$BACKUP_TIME" | cut -d: -f1); if ! command -v crond &> /dev/null; then pkg install cronie -y; fi; local cron_job="${minute} ${hour} * * * ${SCRIPT_PATH} --run-backup"; (crontab -l 2>/dev/null | grep -v "${SCRIPT_PATH}") | { cat; echo "${cron_job}"; } | crontab -; echo -e "${C_GREEN}自动备份任务已设置为每天 ${BACKUP_TIME} 执行。${C_RESET}"; if ! pgrep -f "crond" > /dev/null; then crond; fi; }
manage_backup() { while true; do clear; load_backup_config; echo -e "${C_CYAN}=== 管理备份设置 ===${C_RESET}"; echo -e "1. 修改备份时间\n2. 修改保留天数\n3. 修改备份目录"; read -p "请输入选项 (默认: 0 返回): " choice; choice=${choice:-0}; case $choice in 1) local hour minute; while true; do read -p "输入新小时 (0-23): " hour; if [[ "$hour" =~ ^[0-9]+$ ]] && [ "$hour" -ge 0 ] && [ "$hour" -le 23 ]; then break; else echo -e "${C_RED}无效。${C_RESET}"; fi; done; while true; do read -p "输入新分钟 (0-59): " minute; if [[ "$minute" =~ ^[0-9]+$ ]] && [ "$minute" -ge 0 ] && [ "$minute" -le 59 ]; then break; else echo -e "${C_RED}无效。${C_RESET}"; fi; done; local new_time=$(printf "%02d:%02d" "$hour" "$minute"); sed -i "s|BACKUP_TIME=.*|BACKUP_TIME=\"${new_time}\"|" "${CONFIG_FILE}"; install_cron_job; echo -e "${C_GREEN}时间已更新。${C_RESET}"; sleep 1 ;; 2) read -p "输入新保留天数: " new_days; if [[ "$new_days" =~ ^[0-9]+$ ]]; then sed -i "s|BACKUP_DAYS=.*|BACKUP_DAYS=\"${new_days}\"|" "${CONFIG_FILE}" && echo -e "${C_GREEN}已更新。${C_RESET}"; else echo -e "${C_RED}请输入数字。${C_RESET}"; fi; sleep 1 ;; 3) read -p "输入新备份目录: " new_dir; sed -i "s|BACKUP_DIR=.*|BACKUP_DIR=\"${new_dir}\"|" "${CONFIG_FILE}" && echo -e "${C_GREEN}已更新。${C_RESET}"; sleep 1 ;; 0) break ;; *) echo -e "${C_RED}无效选项。${C_RESET}"; sleep 1 ;; esac; done; }
manual_backup() { if [ ! -f "${CONFIG_FILE}" ]; then echo -e "${C_YELLOW}请先配置备份 (选项 2)。${C_RESET}"; sleep 2; return; fi; echo -e "${C_YELLOW}正在执行备份...${C_RESET}"; if run_backup; then echo -e "${C_GREEN}手动备份成功！${C_RESET}"; else echo -e "${C_RED}手动备份失败，请检查日志: ${LOG_FILE}${C_RESET}"; fi; read -p "按回车键返回..."; }

# --- ClewdR 代理功能 ---
# 检测 CPU 架构，映射到 clewdr 的发布产物命名（clewdr-android-<arch>.zip）
detect_clewdr_arch() {
    case "$(uname -m)" in
        aarch64|arm64) echo "aarch64" ;;
        x86_64|amd64)  echo "x86_64" ;;
        *) echo "" ;;
    esac
}

clewdr_is_installed() { [ -x "${CLEWDR_BIN}" ]; }

# 读取 clewdr.toml 中某个键的值（去掉引号），用于展示监听端口等
get_toml_value() {
    local key="$1"
    [ -f "${CLEWDR_CONFIG}" ] || return 1
    grep -E "^\s*${key}\s*=" "${CLEWDR_CONFIG}" | head -n1 | sed -E "s/^[^=]*=\s*//; s/^\"//; s/\"\s*$//"
}

# 在 clewdr.toml 中设置键值：存在则替换，不存在则追加。value 需自带引号（字符串）或为裸数字。
set_toml_kv() {
    local key="$1" value="$2"
    mkdir -p "${CLEWDR_DIR}"; touch "${CLEWDR_CONFIG}"
    if grep -qE "^\s*${key}\s*=" "${CLEWDR_CONFIG}"; then
        sed -i "s|^\s*${key}\s*=.*|${key} = ${value}|" "${CLEWDR_CONFIG}"
    else
        echo "${key} = ${value}" >> "${CLEWDR_CONFIG}"
    fi
}

install_clewdr() {
    echo -e "${C_CYAN}=== 安装 / 更新 ClewdR ===${C_RESET}"
    if ! command -v unzip >/dev/null 2>&1; then pkg install unzip -y; fi
    local arch; arch=$(detect_clewdr_arch)
    if [ -z "$arch" ]; then
        echo -e "${C_RED}不支持的 CPU 架构: $(uname -m)。ClewdR 仅提供 aarch64 / x86_64 版本。${C_RESET}"
        read -p "按回车返回..."; return
    fi
    local asset="clewdr-android-${arch}.zip"
    local url="https://github.com/${CLEWDR_REPO}/releases/latest/download/${asset}"
    mkdir -p "${CLEWDR_DIR}"
    local tmpzip; tmpzip=$(mktemp)
    echo -e "${C_YELLOW}正在下载 ${asset} ...${C_RESET}"
    if ! http_download "$url" "$tmpzip"; then
        echo -e "${C_RED}下载失败，请检查网络（GitHub 连接）。${C_RESET}"; rm -f "$tmpzip"; read -p "按回车返回..."; return
    fi
    if ! unzip -o "$tmpzip" -d "${CLEWDR_DIR}" >/dev/null; then
        echo -e "${C_RED}解压失败，下载的文件可能不完整。${C_RESET}"; rm -f "$tmpzip"; read -p "按回车返回..."; return
    fi
    rm -f "$tmpzip"
    chmod +x "${CLEWDR_BIN}" 2>/dev/null
    if clewdr_is_installed; then
        echo -e "${C_GREEN}ClewdR 已就绪：${CLEWDR_BIN}${C_RESET}"
        echo -e "${C_YELLOW}提示：首次启动前需设置管理面板密码与 API 密码（必填），启动时会提示。凭证(Cookie)非必填，可后续在网页面板添加。${C_RESET}"
    else
        echo -e "${C_RED}安装异常：未找到可执行文件。${C_RESET}"
    fi
    read -p "按回车返回..."
}

configure_clewdr() {
    echo -e "${C_CYAN}=== 配置 ClewdR 变量 ===${C_RESET}"
    echo -e "${C_YELLOW}其中 管理面板密码 与 API 密码 为必填；IP / 端口 / 代理 可回车保持默认或留空。${C_RESET}"
    mkdir -p "${CLEWDR_DIR}"

    # 监听地址
    echo -e "监听地址: [1] 仅本机 127.0.0.1 (默认)  [2] 局域网 0.0.0.0 (同网络其它设备可访问)"
    read -p "请选择 (默认 1): " ip_choice
    case "${ip_choice:-1}" in
        2) set_toml_kv "ip" "\"0.0.0.0\"";;
        *) set_toml_kv "ip" "\"127.0.0.1\"";;
    esac

    # 端口
    local cur_port; cur_port=$(get_toml_value "port"); cur_port=${cur_port:-8484}
    while true; do
        read -p "监听端口 (默认 ${cur_port}): " port
        port=${port:-$cur_port}
        if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then set_toml_kv "port" "$port"; break; else echo -e "${C_RED}端口无效。${C_RESET}"; fi
    done

    # 管理面板密码（必填）
    local cur_admin; cur_admin=$(get_toml_value "admin_password")
    local admin_pw=""
    while [ -z "$admin_pw" ]; do
        read -p "管理面板密码 admin_password (必填${cur_admin:+, 回车沿用当前}): " admin_pw
        [ -z "$admin_pw" ] && [ -n "$cur_admin" ] && admin_pw="$cur_admin"
        [ -z "$admin_pw" ] && echo -e "${C_RED}不能为空。${C_RESET}"
    done
    set_toml_kv "admin_password" "\"${admin_pw}\""

    # API 访问密码（必填）
    local cur_api; cur_api=$(get_toml_value "password")
    local api_pw=""
    while [ -z "$api_pw" ]; do
        read -p "API 访问密码 password (客户端连接用, 必填${cur_api:+, 回车沿用当前}): " api_pw
        [ -z "$api_pw" ] && [ -n "$cur_api" ] && api_pw="$cur_api"
        [ -z "$api_pw" ] && echo -e "${C_RED}不能为空。${C_RESET}"
    done
    set_toml_kv "password" "\"${api_pw}\""

    # 出站代理（可选）
    read -p "出站代理 proxy (如 http://127.0.0.1:7890, 可选, 回车跳过): " proxy
    [ -n "$proxy" ] && set_toml_kv "proxy" "\"${proxy}\""

    echo -e "${C_GREEN}配置已写入 ${CLEWDR_CONFIG}${C_RESET}"
    read -p "按回车返回..."
}

# 确保管理面板密码与 API 密码已设置（二者必填），未设置则现场要求填写
ensure_clewdr_credentials() {
    local admin_pw api_pw
    admin_pw=$(get_toml_value "admin_password")
    api_pw=$(get_toml_value "password")
    [ -n "$admin_pw" ] && [ -n "$api_pw" ] && return 0
    echo -e "${C_YELLOW}启动前需先设置 ClewdR 的管理面板密码与 API 密码（均为必填）。${C_RESET}"
    while [ -z "$admin_pw" ]; do read -p "设置管理面板密码 admin_password: " admin_pw; [ -z "$admin_pw" ] && echo -e "${C_RED}不能为空。${C_RESET}"; done
    set_toml_kv "admin_password" "\"${admin_pw}\""
    while [ -z "$api_pw" ]; do read -p "设置 API 访问密码 password: " api_pw; [ -z "$api_pw" ] && echo -e "${C_RED}不能为空。${C_RESET}"; done
    set_toml_kv "password" "\"${api_pw}\""
    echo -e "${C_GREEN}密码已保存到 ${CLEWDR_CONFIG}${C_RESET}"
}

# 在终端醒目地打印 WebUI 管理地址
print_clewdr_webui() {
    local port; port=$(get_toml_value "port"); port=${port:-8484}
    echo -e "${C_GREEN}================================================${C_RESET}"
    echo -e "${C_GREEN}  ClewdR WebUI 管理地址: http://127.0.0.1:${port}${C_RESET}"
    echo -e "${C_GREEN}================================================${C_RESET}"
}

# 后台启动 ClewdR（供“启动 SillyTavern 前先启动 ClewdR”使用，不阻塞终端）
start_clewdr_background() {
    clewdr_is_installed || { echo -e "${C_RED}尚未安装 ClewdR。${C_RESET}"; return 1; }
    ensure_clewdr_credentials
    if pgrep -x clewdr >/dev/null 2>&1; then
        echo -e "${C_GREEN}ClewdR 已在后台运行。${C_RESET}"
    else
        cd "${CLEWDR_DIR}" || { echo -e "${C_RED}无法进入目录 ${CLEWDR_DIR}${C_RESET}"; return 1; }
        LD_LIBRARY_PATH="${CLEWDR_DIR}:${LD_LIBRARY_PATH}" nohup ./clewdr > "${CLEWDR_DIR}/clewdr.log" 2>&1 &
        sleep 1
        if pgrep -x clewdr >/dev/null 2>&1; then
            echo -e "${C_GREEN}ClewdR 已在后台启动（日志: ${CLEWDR_DIR}/clewdr.log）。${C_RESET}"
        else
            echo -e "${C_RED}ClewdR 后台启动失败，请查看日志: ${CLEWDR_DIR}/clewdr.log${C_RESET}"; return 1
        fi
    fi
    print_clewdr_webui
}

start_clewdr() {
    echo -e "${C_CYAN}=== 启动 ClewdR ===${C_RESET}"
    if ! clewdr_is_installed; then
        echo -e "${C_RED}尚未安装 ClewdR，请先使用菜单“安装/更新 ClewdR”。${C_RESET}"; sleep 2; return
    fi
    ensure_clewdr_credentials
    print_clewdr_webui
    echo -e "${C_YELLOW}下方为 ClewdR 运行日志，按 Ctrl+C 可停止并返回。${C_RESET}"
    cd "${CLEWDR_DIR}" || { echo -e "${C_RED}无法进入目录 ${CLEWDR_DIR}${C_RESET}"; return; }
    # Android 版依赖同目录下的 libc++_shared.so，需通过 LD_LIBRARY_PATH 让动态链接器找到它
    LD_LIBRARY_PATH="${CLEWDR_DIR}:${LD_LIBRARY_PATH}" ./clewdr
    read -p "ClewdR 已退出，按回车返回..."
}

# --- 脚本更新---
update_self() {
    echo -e "${C_CYAN}=== 检查管理器脚本更新 ===${C_RESET}"; local temp_file=$(mktemp)
    if ! http_download "${SCRIPT_URL}" "${temp_file}"; then
        echo -e "${C_RED}下载失败。${C_RESET}"; rm -f "${temp_file}"; read -p "按回车返回..."; return
    fi
    if cmp -s "${SCRIPT_PATH}" "${temp_file}"; then
        echo -e "${C_GREEN}已是最新版本。${C_RESET}"; rm -f "${temp_file}"
    else
        echo -e "${C_GREEN}发现新版本！正在自动更新...${C_RESET}"
        if bash -n "${temp_file}"; then
            mv "${temp_file}" "${SCRIPT_PATH}"; chmod +x "${SCRIPT_PATH}"
            echo -e "${C_GREEN}更新成功！脚本将重启...${C_RESET}"; sleep 2
            exec bash "${SCRIPT_PATH}"
        else
            echo -e "${C_RED}错误：下载的新脚本存在语法问题，已取消更新以防出错。${C_RESET}"
            rm -f "${temp_file}"
        fi
    fi
    read -p "按回车键返回...";
}

setup_script() {
    echo -e "${C_CYAN}=== SillyTavern 管理器首次设置 ===${C_RESET}"
    ensure_dirs
    cp "$0" "${SCRIPT_PATH}"
    chmod +x "${SCRIPT_PATH}"
    local bashrc_file="${HOME}/.bashrc"
    local start_command="bash ${SCRIPT_PATH}"
    if ! grep -qF "${start_command}" "${bashrc_file}"; then
        echo -e "\n# Auto-start SillyTavern Manager\n${start_command}" >> "${bashrc_file}"
        echo -e "${C_GREEN}已设置 Termux 启动时自动运行。${C_RESET}"
    fi
    echo -e "${C_GREEN}设置完成！正在进入主菜单...${C_RESET}"; sleep 2
    exec bash "${SCRIPT_PATH}"
}

# --- 主菜单 ---
main_menu() {
    while true; do
        fetch_remote_versions
        clear
        local local_version_info="未安装"
        local main_option_text="安装 SillyTavern"
        local is_installed=false
        if [ -d "${ST_DIR}" ] && [ -f "${ST_DIR}/package.json" ]; then
            local st_version=$(parse_pkg_version "$(cat "${ST_DIR}/package.json")")
            local st_branch=$(cd "${ST_DIR}" && git rev-parse --abbrev-ref HEAD)
            local_version_info="${st_version} (${st_branch})"
            main_option_text="启动 SillyTavern"
            is_installed=true
        fi
        echo -e "${C_BLUE}=======================================${C_RESET}"
        echo -e "${C_CYAN}      SillyTavern 管理器  v${MANAGER_VERSION}      ${C_RESET}"
        echo -e "${C_BLUE}=======================================${C_RESET}"
        local clewdr_status="未安装"
        if clewdr_is_installed; then clewdr_status="已安装"; fi
        printf "${C_YELLOW}%-18s ${C_GREEN}%s\n" "本地版本:" "$local_version_info"
        printf "${C_YELLOW}%-18s ${C_CYAN}%s\n" "远程 Release:" "$RELEASE_VER"
        printf "${C_YELLOW}%-18s ${C_CYAN}%s\n" "远程 Staging:" "$STAGING_VER"
        printf "${C_YELLOW}%-18s ${C_CYAN}%s\n" "ClewdR:" "$clewdr_status"
        echo -e "${C_BLUE}---------------------------------------${C_RESET}"
        echo -e "  ${C_GREEN}0. ${main_option_text}${C_RESET} (默认)"
        echo "  1. 更新 SillyTavern"
        echo ""
        echo -e "${C_CYAN}--- 数据备份 ---${C_RESET}"
        if [ -f "${CONFIG_FILE}" ]; then echo "  2. 管理备份设置"; else echo "  2. 安装/配置备份功能"; fi
        echo "  3. 立即手动备份一次"
        echo ""
        echo -e "${C_CYAN}--- ClewdR 代理 ---${C_RESET}"
        if clewdr_is_installed; then echo "  5. 更新 ClewdR"; else echo "  5. 安装 ClewdR"; fi
        echo "  6. 启动 ClewdR"
        echo "  7. 配置 ClewdR 变量"
        echo ""
        echo -e "${C_CYAN}--- 管理器 ---${C_RESET}"
        echo "  4. 更新管理器脚本"
        echo "  8. 退出脚本"
        echo -e "${C_BLUE}---------------------------------------${C_RESET}"
        read -p "请输入选项 (默认: 0): " choice; choice=${choice:-0}
        case $choice in
            0) if $is_installed; then start_sillytavern; else install_sillytavern; fi ;;
            1) if $is_installed; then update_sillytavern; else echo -e "${C_RED}请先安装 (选项0)。${C_RESET}"; sleep 1; fi ;;
            2) if $is_installed; then if [ -f "${CONFIG_FILE}" ]; then manage_backup; else setup_backup; read -p "按回车返回。"; fi; else echo -e "${C_RED}请先安装 (选项0)。${C_RESET}"; sleep 1; fi ;;
            3) if $is_installed; then manual_backup; else echo -e "${C_RED}请先安装 (选项0)。${C_RESET}"; sleep 1; fi ;;
            4) update_self ;;
            5) install_clewdr ;;
            6) start_clewdr ;;
            7) configure_clewdr ;;
            8) echo "退出脚本。"; exit 0 ;;
            *) echo -e "${C_RED}无效选项。${C_RESET}"; sleep 1 ;;
        esac
    done
}

# --- 脚本入口 ---
case "$1" in
    --run-backup) ensure_dirs; run_backup ;;
    *) if [ "$(realpath "$0")" != "${SCRIPT_PATH}" ]; then setup_script; else main_menu; fi ;;
esac

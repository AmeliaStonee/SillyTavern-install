#!/data/data/com/termux/files/usr/bin/bash

export PATH="/data/data/com.termux/files/usr/bin:$PATH"

ST_DIR_NAME="SillyTavern"
ST_DIR="${HOME}/${ST_DIR_NAME}"
ST_DATA_USER_SUBPATH="data/default-user"
SCRIPT_INSTALL_DIR="${HOME}/.st-manager"
SCRIPT_PATH="${SCRIPT_INSTALL_DIR}/st-manager.sh"
CONFIG_FILE="${SCRIPT_INSTALL_DIR}/config.conf"
LOG_FILE="${SCRIPT_INSTALL_DIR}/backup.log"
SCRIPT_URL="https://raw.githubusercontent.com/AmeliaStonee/SillyTavern-install/main/st-manager.sh"

C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "${LOG_FILE}"
}

ensure_dirs() {
    mkdir -p "${SCRIPT_INSTALL_DIR}"
}

# --- 版本获取 ---
fetch_remote_versions() {
    echo -e "${C_YELLOW}正在从 GitHub 查询最新版本...${C_RESET}"
    local release_url="https://raw.githubusercontent.com/SillyTavern/SillyTavern/main/package.json"
    local staging_url="https://raw.githubusercontent.com/SillyTavern/SillyTavern/staging/package.json"
    
    # 使用 wget 获取内容，检查退出码判断是否成功
    local release_json=$(wget -qO- --timeout=5 "$release_url")
    if [ $? -eq 0 ] && [ -n "$release_json" ]; then
        RELEASE_VER=$(echo "$release_json" | grep '"version":' | sed 's/.*: "\(.*\)".*/\1/')
    else
        RELEASE_VER="查询失败"
    fi

    local staging_json=$(wget -qO- --timeout=5 "$staging_url")
    if [ $? -eq 0 ] && [ -n "$staging_json" ]; then
        STAGING_VER=$(echo "$staging_json" | grep '"version":' | sed 's/.*: "\(.*\)".*/\1/')
    else
        STAGING_VER="查询失败"
    fi
}

# --- SillyTavern 核心功能 ---
install_sillytavern() {
    echo -e "${C_CYAN}=== 开始安装 SillyTavern ===${C_RESET}"
    pkg update -y && pkg upgrade -y
    pkg install git nodejs esbuild cronie zip unzip -y
    read -p "您想安装哪个分支？[1] release (稳定版) [2] staging (开发版, 默认): " branch_choice
    branch_choice=${branch_choice:-2}
    if [[ "$branch_choice" == "1" ]]; then
        git clone https://github.com/SillyTavern/SillyTavern "${ST_DIR}"
    else
        git clone -b staging https://github.com/SillyTavern/SillyTavern "${ST_DIR}"
    fi
    if [ ! -d "${ST_DIR}" ]; then echo -e "${C_RED}克隆失败，请检查网络。${C_RESET}"; exit 1; fi
    cd "${ST_DIR}" || exit
    npm install
    if [ -f "start.sh" ]; then
        echo -e "${C_GREEN}SillyTavern 安装成功！建议配置备份。${C_RESET}"; sleep 2; setup_backup
    else
        echo -e "${C_RED}安装失败，start.sh 未找到。${C_RESET}"; exit 1
    fi
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
    cd "${ST_DIR}" || { echo -e "${C_RED}错误: 无法进入目录 ${ST_DIR}${C_RESET}"; exit 1; }
    bash start.sh
}

update_sillytavern() {
    echo -e "${C_CYAN}=== 更新 SillyTavern ===${C_RESET}"
    cd "${ST_DIR}" || exit
    echo "请选择操作:"
    echo "1. 拉取当前分支的最新更新"
    echo "2. 切换到其他分支"
    read -p "请输入选项 (默认: 0 返回): " choice
    choice=${choice:-0}
    case $choice in
        1)
            git pull && npm install
            echo -e "${C_GREEN}更新完成！${C_RESET}"
            ;;
        2)
            echo "选择要切换到的分支: [1] release (稳定版) [2] staging (开发版)"
            read -p "请输入选项: " branch_switch_choice
            case $branch_switch_choice in
                1) git switch main && git pull && npm install && echo -e "${C_GREEN}已切换到 release 分支并更新。${C_RESET}" ;;
                2) git switch staging && git pull && npm install && echo -e "${C_GREEN}已切换到 staging 分支并更新。${C_RESET}" ;;
                *) echo -e "${C_RED}无效选项。${C_RESET}" ;;
            esac
            ;;
        0) return ;;
        *) echo -e "${C_RED}无效选项。${C_RESET}" ;;
    esac
    read -p "按回车键返回主菜单..."
}

# --- 备份功能 ---
load_backup_config() { if [ -f "${CONFIG_FILE}" ]; then source "${CONFIG_FILE}"; else BACKUP_DIR=""; BACKUP_DAYS=""; BACKUP_TIME=""; fi; }
run_backup() { load_backup_config; if [ -z "${BACKUP_DIR}" ]; then log "备份失败：未配置"; return 1; fi; local data_dir="${ST_DIR}/${ST_DATA_USER_SUBPATH}"; if [ ! -d "${data_dir}" ]; then log "备份失败：找不到数据目录"; return 1; fi; mkdir -p "${BACKUP_DIR}"; local timestamp=$(date +%Y%m%d-%H%M); local filename="SillyTavern-Backup-${timestamp}.zip"; log "开始备份到 ${filename}"; local parent_dir=$(dirname "${data_dir}"); local user_data_folder=$(basename "${data_dir}"); pushd "${parent_dir}" > /dev/null; zip -r "${BACKUP_DIR}/${filename}" "${user_data_folder}"; popd > /dev/null; log "清理旧备份..."; find "${BACKUP_DIR}" -name "SillyTavern-Backup-*.zip" -mtime +"${BACKUP_DAYS}" -exec rm {} \;; log "清理完成"; return 0; }
setup_backup() { echo -e "${C_CYAN}=== 配置自动备份 ===${C_RESET}"; local default_backup_dir="${HOME}/SillyTavern-Backups"; read -p "请输入备份目录 (默认: ${default_backup_dir}): " backup_dir; BACKUP_DIR=${backup_dir:-${default_backup_dir}}; read -p "保留最近多少天？ (默认: 7): " backup_days; BACKUP_DAYS=${backup_days:-7}; local hour minute; while true; do read -p "设置备份小时 (0-23): " hour; if [[ "$hour" =~ ^[0-9]+$ ]] && [ "$hour" -ge 0 ] && [ "$hour" -le 23 ]; then break; else echo -e "${C_RED}输入无效。${C_RESET}"; fi; done; while true; do read -p "设置备份分钟 (0-59): " minute; if [[ "$minute" =~ ^[0-9]+$ ]] && [ "$minute" -ge 0 ] && [ "$minute" -le 59 ]; then break; else echo -e "${C_RED}输入无效。${C_RESET}"; fi; done; BACKUP_TIME=$(printf "%02d:%02d" "$hour" "$minute"); mkdir -p "${SCRIPT_INSTALL_DIR}"; echo "BACKUP_DIR=\"${BACKUP_DIR}\"" > "${CONFIG_FILE}"; echo "BACKUP_DAYS=\"${BACKUP_DAYS}\"" >> "${CONFIG_FILE}"; echo "BACKUP_TIME=\"${BACKUP_TIME}\"" >> "${CONFIG_FILE}"; echo -e "${C_GREEN}配置已保存。${C_RESET}"; install_cron_job; }
install_cron_job() { load_backup_config; if [ -z "${BACKUP_TIME}" ]; then return; fi; local minute=$(echo "$BACKUP_TIME" | cut -d: -f2); local hour=$(echo "$BACKUP_TIME" | cut -d: -f1); if ! command -v crond &> /dev/null; then pkg install cronie -y; fi; local cron_job="${minute} ${hour} * * * ${SCRIPT_PATH} --run-backup"; (crontab -l 2>/dev/null | grep -v "${SCRIPT_PATH}") | { cat; echo "${cron_job}"; } | crontab -; echo -e "${C_GREEN}自动备份任务已设置为每天 ${BACKUP_TIME} 执行。${C_RESET}"; if ! pgrep -f "crond" > /dev/null; then crond; fi; }
manage_backup() { while true; do clear; load_backup_config; echo -e "${C_CYAN}=== 管理备份设置 ===${C_RESET}"; echo -e "1. 修改备份时间\n2. 修改保留天数\n3. 修改备份目录"; read -p "请输入选项 (默认: 0 返回): " choice; choice=${choice:-0}; case $choice in 1) local hour minute; while true; do read -p "输入新小时 (0-23): " hour; if [[ "$hour" =~ ^[0-9]+$ ]] && [ "$hour" -ge 0 ] && [ "$hour" -le 23 ]; then break; else echo -e "${C_RED}无效。${C_RESET}"; fi; done; while true; do read -p "输入新分钟 (0-59): " minute; if [[ "$minute" =~ ^[0-9]+$ ]] && [ "$minute" -ge 0 ] && [ "$minute" -le 59 ]; then break; else echo -e "${C_RED}无效。${C_RESET}"; fi; done; local new_time=$(printf "%02d:%02d" "$hour" "$minute"); sed -i "s|BACKUP_TIME=.*|BACKUP_TIME=\"${new_time}\"|" "${CONFIG_FILE}"; install_cron_job; echo -e "${C_GREEN}时间已更新。${C_RESET}"; sleep 1 ;; 2) read -p "输入新保留天数: " new_days; if [[ "$new_days" =~ ^[0-9]+$ ]]; then sed -i "s|BACKUP_DAYS=.*|BACKUP_DAYS=\"${new_days}\"|" "${CONFIG_FILE}" && echo -e "${C_GREEN}已更新。${C_RESET}"; else echo -e "${C_RED}请输入数字。${C_RESET}"; fi; sleep 1 ;; 3) read -p "输入新备份目录: " new_dir; sed -i "s|BACKUP_DIR=.*|BACKUP_DIR=\"${new_dir}\"|" "${CONFIG_FILE}" && echo -e "${C_GREEN}已更新。${C_RESET}"; sleep 1 ;; 0) break ;; *) echo -e "${C_RED}无效选项。${C_RESET}"; sleep 1 ;; esac; done; }
manual_backup() { if [ ! -f "${CONFIG_FILE}" ]; then echo -e "${C_YELLOW}请先配置备份 (选项 2)。${C_RESET}"; sleep 2; return; fi; echo -e "${C_YELLOW}正在执行备份...${C_RESET}"; if run_backup; then echo -e "${C_GREEN}手动备份成功！${C_RESET}"; else echo -e "${C_RED}手动备份失败，请检查日志: ${LOG_FILE}${C_RESET}"; fi; read -p "按回车键返回..."; }

# --- 管理器自身功能 ---
update_self() { echo -e "${C_CYAN}=== 检查管理器脚本更新 ===${C_RESET}"; local temp_file=$(mktemp); if ! wget -q -O "${temp_file}" "${SCRIPT_URL}"; then echo -e "${C_RED}下载失败。${C_RESET}"; rm -f "${temp_file}"; read -p "按回车返回..."; return; fi; if cmp -s "${SCRIPT_PATH}" "${temp_file}"; then echo -e "${C_GREEN}已是最新版本。${C_RESET}"; rm -f "${temp_file}"; else echo -e "${C_GREEN}发现新版本！正在自动更新...${C_RESET}"; mv "${temp_file}" "${SCRIPT_PATH}"; chmod +x "${SCRIPT_PATH}"; echo -e "${C_GREEN}更新成功！脚本将重启...${C_RESET}"; sleep 2; exec bash "${SCRIPT_PATH}"; fi; read -p "按回车键返回..."; }
setup_script() { echo -e "${C_CYAN}=== SillyTavern 管理器首次设置 ===${C_RESET}"; ensure_dirs; cp "$0" "${SCRIPT_PATH}"; chmod +x "${SCRIPT_PATH}"; local bashrc_file="${HOME}/.bashrc"; local start_command="bash ${SCRIPT_PATH}"; if ! grep -qF "${start_command}" "${bashrc_file}"; then echo -e "\n# 自动启动 SillyTavern 管理器\n${start_command}" >> "${bashrc_file}"; echo -e "${C_GREEN}已设置 Termux 启动时自动运行。${C_RESET}"; fi; echo -e "${C_GREEN}设置完成！正在进入主菜单...${C_RESET}"; sleep 2; exec bash "${SCRIPT_PATH}"; }

# --- 主菜单 ---
main_menu() {
    while true; do
        fetch_remote_versions # 关键修复：每次循环都重新获取远程版本
        clear
        local local_version_info="未安装"
        local main_option_text="安装 SillyTavern"
        local is_installed=false
        if [ -d "${ST_DIR}" ] && [ -f "${ST_DIR}/package.json" ]; then
            local st_version=$(grep '"version":' "${ST_DIR}/package.json" | sed 's/.*: "\(.*\)".*/\1/')
            local st_branch=$(cd "${ST_DIR}" && git rev-parse --abbrev-ref HEAD)
            local_version_info="${st_version} (${st_branch})" # 修复：合并版本和分支
            main_option_text="启动 SillyTavern"
            is_installed=true
        fi

        echo -e "${C_BLUE}=======================================${C_RESET}"
        echo -e "${C_CYAN}        SillyTavern 管理器           ${C_RESET}"
        echo -e "${C_BLUE}=======================================${C_RESET}"
        printf "${C_YELLOW}%-18s ${C_GREEN}%s\n" "本地版本:" "$local_version_info"
        printf "${C_YELLOW}%-18s ${C_CYAN}%s\n" "远程 Release:" "$RELEASE_VER"
        printf "${C_YELLOW}%-18s ${C_CYAN}%s\n" "远程 Staging:" "$STAGING_VER"
        echo -e "${C_BLUE}---------------------------------------${C_RESET}"
        
        echo -e "  ${C_GREEN}0. ${main_option_text}${C_RESET} (默认)"
        echo "  1. 更新 SillyTavern"
        echo ""
        echo -e "${C_CYAN}--- 数据备份 ---${C_RESET}"
        if [ -f "${CONFIG_FILE}" ]; then echo "  2. 管理备份设置"; else echo "  2. 安装/配置备份功能"; fi
        echo "  3. 立即手动备份一次"
        echo ""
        echo -e "${C_CYAN}--- 管理器 ---${C_RESET}"
        echo "  4. 更新管理器脚本"
        echo "  5. 退出脚本"
        echo -e "${C_BLUE}---------------------------------------${C_RESET}"
        
        read -p "请输入选项 (默认: 0): " choice
        choice=${choice:-0}

        case $choice in
            0) if $is_installed; then start_sillytavern; else install_sillytavern; fi ;;
            1) if $is_installed; then update_sillytavern; else echo -e "${C_RED}请先安装 (选项0)。${C_RESET}"; sleep 1; fi ;;
            2) if $is_installed; then if [ -f "${CONFIG_FILE}" ]; then manage_backup; else setup_backup; read -p "按回车返回。"; fi; else echo -e "${C_RED}请先安装 (选项0)。${C_RESET}"; sleep 1; fi ;;
            3) if $is_installed; then manual_backup; else echo -e "${C_RED}请先安装 (选项0)。${C_RESET}"; sleep 1; fi ;;
            4) update_self ;;
            5) echo "退出脚本。"; exit 0 ;;
            *) echo -e "${C_RED}无效选项。${C_RESET}"; sleep 1 ;;
        esac
    done
}

# --- 脚本入口 ---
case "$1" in
    --run-backup) ensure_dirs; run_backup ;;
    *) if [ "$(realpath "$0")" != "${SCRIPT_PATH}" ]; then setup_script; else main_menu; fi ;;
esac
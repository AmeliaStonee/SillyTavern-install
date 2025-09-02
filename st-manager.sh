#!/data/data/com/termux/files/usr/bin/bash

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

# --- SillyTavern 核心功能 ---
install_sillytavern() {
    echo -e "${C_CYAN}=== 开始安装 SillyTavern ===${C_RESET}"
    echo -e "${C_YELLOW}步骤 1/5: 更新软件包列表...${C_RESET}"
    pkg update -y && pkg upgrade -y
    echo -e "${C_YELLOW}步骤 2/5: 安装依赖 (git, nodejs, esbuild, cronie, zip)...${C_RESET}"
    pkg install git nodejs esbuild cronie zip unzip -y
    if ! command -v crond &> /dev/null; then
        echo -e "${C_RED}错误：cronie (定时任务服务) 安装失败。自动备份功能将不可用。${C_RESET}"
    fi
    echo -e "${C_YELLOW}步骤 3/5: 从 GitHub 克隆 SillyTavern...${C_RESET}"
    read -p "您想安装哪个分支？[1] release (稳定版) [2] staging (开发版, 默认): " branch_choice
    branch_choice=${branch_choice:-2}
    if [[ "$branch_choice" == "1" ]]; then
        git clone https://github.com/SillyTavern/SillyTavern "${ST_DIR}"
    else
        git clone -b staging https://github.com/SillyTavern/SillyTavern "${ST_DIR}"
    fi
    if [ ! -d "${ST_DIR}" ]; then
        echo -e "${C_RED}错误：克隆 SillyTavern 失败，请检查网络连接。${C_RESET}"
        exit 1
    fi
    cd "${ST_DIR}" || exit
    echo -e "${C_YELLOW}步骤 4/5: 安装 Node.js 模块 (npm install)...${C_RESET}"
    npm install
    echo -e "${C_YELLOW}步骤 5/5: 检查安装...${C_RESET}"
    if [ -f "start.sh" ]; then
        echo -e "${C_GREEN}SillyTavern 安装成功！${C_RESET}"
        echo -e "现在建议您配置备份功能。"
        sleep 2
        setup_backup
    else
        echo -e "${C_RED}安装似乎失败了，start.sh 文件未找到。${C_RESET}"
        exit 1
    fi
}

start_sillytavern() {
    echo -e "${C_CYAN}=== 启动 SillyTavern ===${C_RESET}"
    if [ -f "$CONFIG_FILE" ]; then
        if ! pgrep -f "crond" > /dev/null; then
            echo -e "${C_YELLOW}备份服务未运行，正在自动启动...${C_RESET}"
            crond
            echo -e "${C_GREEN}备份服务已启动。${C_RESET}"
        else
             echo -e "${C_GREEN}备份服务正常运行中。${C_RESET}"
        fi
    else
        echo -e "${C_YELLOW}提示：您尚未配置自动备份功能 (菜单选项 2)。${C_RESET}"
    fi
    echo -e "${C_CYAN}正在进入 SillyTavern 目录并执行 start.sh...${C_RESET}"
    cd "${ST_DIR}" || { echo -e "${C_RED}错误: 无法进入目录 ${ST_DIR}${C_RESET}"; exit 1; }
    bash start.sh
}

update_sillytavern() {
    echo -e "${C_CYAN}=== 更新 SillyTavern ===${C_RESET}"
    cd "${ST_DIR}" || exit
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    echo -e "当前所在分支: ${C_GREEN}${current_branch}${C_RESET}"
    echo "请选择操作:"
    echo "1. 拉取当前分支的最新更新 (git pull)"
    echo "2. 切换到其他分支 (release/staging)"
    echo "0. 返回"
    read -p "请输入选项: " update_choice
    case $update_choice in
        1)
            echo -e "${C_YELLOW}正在拉取更新...${C_RESET}"; git pull
            echo -e "${C_YELLOW}正在重新安装依赖...${C_RESET}"; npm install
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
load_backup_config() {
    if [ -f "${CONFIG_FILE}" ]; then source "${CONFIG_FILE}"; else
        BACKUP_DIR=""; BACKUP_DAYS=""; BACKUP_TIME=""
    fi
}

run_backup() {
    load_backup_config
    if [ -z "${BACKUP_DIR}" ] || [ -z "${BACKUP_DAYS}" ]; then log "备份失败：备份未配置。"; return 1; fi
    local data_dir="${ST_DIR}/${ST_DATA_USER_SUBPATH}"
    if [ ! -d "${data_dir}" ]; then log "备份失败：找不到数据目录 ${data_dir}"; return 1; fi
    mkdir -p "${BACKUP_DIR}"
    local timestamp=$(date +%Y%m%d-%H%M)
    local filename="SillyTavern-Backup-${timestamp}.zip"
    log "开始备份到 ${BACKUP_DIR}/${filename}"
    local parent_dir=$(dirname "${data_dir}")
    local user_data_folder=$(basename "${data_dir}")
    pushd "${parent_dir}" > /dev/null
    zip -r "${BACKUP_DIR}/${filename}" "${user_data_folder}"
    local zip_status=$?
    popd > /dev/null
    if [ ${zip_status} -eq 0 ]; then log "备份成功创建：${filename}"; else log "备份失败：zip 命令出错。"; return 1; fi
    log "开始清理 ${BACKUP_DAYS} 天前的旧备份..."; find "${BACKUP_DIR}" -name "SillyTavern-Backup-*.zip" -mtime +"${BACKUP_DAYS}" -exec rm {} \;
    log "清理完成。"; return 0
}

setup_backup() {
    echo -e "${C_CYAN}=== 配置自动备份 ===${C_RESET}"
    local default_backup_dir="${HOME}/SillyTavern-Backups"
    read -p "请输入备份文件存放目录 (默认: ${default_backup_dir}): " backup_dir
    BACKUP_DIR=${backup_dir:-${default_backup_dir}}
    read -p "您想保留最近多少天的备份？ (默认: 7): " backup_days
    BACKUP_DAYS=${backup_days:-7}
    
    # 改进的时间输入
    local hour minute
    while true; do
        read -p "设置每天自动备份的小时 (0-23): " hour
        if [[ "$hour" =~ ^[0-9]+$ ]] && [ "$hour" -ge 0 ] && [ "$hour" -le 23 ]; then break; else echo -e "${C_RED}输入无效，请输入0到23之间的数字。${C_RESET}"; fi
    done
    while true; do
        read -p "设置每天自动备份的分钟 (0-59): " minute
        if [[ "$minute" =~ ^[0-9]+$ ]] && [ "$minute" -ge 0 ] && [ "$minute" -le 59 ]; then break; else echo -e "${C_RED}输入无效，请输入0到59之间的数字。${C_RESET}"; fi
    done
    BACKUP_TIME=$(printf "%02d:%02d" "$hour" "$minute")

    mkdir -p "${SCRIPT_INSTALL_DIR}"
    echo "BACKUP_DIR=\"${BACKUP_DIR}\"" > "${CONFIG_FILE}"
    echo "BACKUP_DAYS=\"${BACKUP_DAYS}\"" >> "${CONFIG_FILE}"
    echo "BACKUP_TIME=\"${BACKUP_TIME}\"" >> "${CONFIG_FILE}"
    echo -e "${C_GREEN}备份配置已保存。${C_RESET}"
    install_cron_job
}

install_cron_job() {
    load_backup_config
    if [ -z "${BACKUP_TIME}" ]; then echo -e "${C_RED}错误: 备份时间未设置。${C_RESET}"; return; fi
    local minute=$(echo "$BACKUP_TIME" | cut -d: -f2)
    local hour=$(echo "$BACKUP_TIME" | cut -d: -f1)
    if ! command -v crond &> /dev/null; then pkg install cronie -y; fi
    local cron_job="${minute} ${hour} * * * ${SCRIPT_PATH} --run-backup"
    (crontab -l 2>/dev/null | grep -v "${SCRIPT_PATH}") | { cat; echo "${cron_job}"; } | crontab -
    echo -e "${C_GREEN}自动备份任务已设置为每天 ${BACKUP_TIME} 执行。${C_RESET}"
    if ! pgrep -f "crond" > /dev/null; then crond; echo -e "${C_GREEN}定时服务 (crond) 已启动。${C_RESET}"; fi
}

manage_backup() {
    while true; do
        clear; load_backup_config
        echo -e "${C_CYAN}=== 管理备份设置 ===${C_RESET}"
        echo -e "当前设置:\n  备份目录: ${C_GREEN}${BACKUP_DIR}${C_RESET}\n  保留天数: ${C_GREEN}${BACKUP_DAYS}${C_RESET}\n  备份时间: ${C_GREEN}${BACKUP_TIME}${C_RESET}"
        echo "------------------------"
        echo "1. 修改自动备份的时间"; echo "2. 修改自动备份数据的天数"; echo "3. 修改备份文件夹目录"; echo "0. 返回主菜单"
        read -p "请输入选项: " choice
        case $choice in
            1)
                local hour minute
                while true; do read -p "输入新的小时 (0-23): " hour; if [[ "$hour" =~ ^[0-9]+$ ]] && [ "$hour" -ge 0 ] && [ "$hour" -le 23 ]; then break; else echo -e "${C_RED}无效输入。${C_RESET}"; fi; done
                while true; do read -p "输入新的分钟 (0-59): " minute; if [[ "$minute" =~ ^[0-9]+$ ]] && [ "$minute" -ge 0 ] && [ "$minute" -le 59 ]; then break; else echo -e "${C_RED}无效输入。${C_RESET}"; fi; done
                local new_time=$(printf "%02d:%02d" "$hour" "$minute")
                sed -i "s|BACKUP_TIME=.*|BACKUP_TIME=\"${new_time}\"|" "${CONFIG_FILE}"
                install_cron_job # <- 关键修复：重新应用定时任务
                echo -e "${C_GREEN}时间已更新并应用。${C_RESET}"; sleep 1 ;;
            2)
                read -p "输入新的保留天数: " new_days
                if [[ "$new_days" =~ ^[0-9]+$ ]]; then sed -i "s|BACKUP_DAYS=.*|BACKUP_DAYS=\"${new_days}\"|" "${CONFIG_FILE}" && echo -e "${C_GREEN}已更新。${C_RESET}"; else echo -e "${C_RED}请输入数字。${C_RESET}"; fi; sleep 1 ;;
            3)
                read -p "输入新的备份目录: " new_dir
                sed -i "s|BACKUP_DIR=.*|BACKUP_DIR=\"${new_dir}\"|" "${CONFIG_FILE}" && echo -e "${C_GREEN}已更新。${C_RESET}"; sleep 1 ;;
            0) break ;;
            *) echo -e "${C_RED}无效选项。${C_RESET}"; sleep 1 ;;
        esac
    done
}

manual_backup() {
    echo -e "${C_CYAN}=== 手动备份 ===${C_RESET}"
    if [ ! -f "${CONFIG_FILE}" ]; then echo -e "${C_YELLOW}请先配置备份 (选项 2)。${C_RESET}"; sleep 2; return; fi
    echo -e "${C_YELLOW}正在执行备份...${C_RESET}"
    if run_backup; then echo -e "${C_GREEN}手动备份成功！${C_RESET}"; else echo -e "${C_RED}手动备份失败，请检查日志: ${LOG_FILE}${C_RESET}"; fi
    read -p "按回车键返回主菜单..."
}

# --- 管理器自身功能 ---
update_self() {
    echo -e "${C_CYAN}=== 检查管理器脚本更新 ===${C_RESET}"
    local temp_file=$(mktemp)
    echo -e "${C_YELLOW}正在从 GitHub 下载最新版本...${C_RESET}"
    if ! wget -q -O "${temp_file}" "${SCRIPT_URL}"; then
        echo -e "${C_RED}下载失败，请检查网络。${C_RESET}"; rm -f "${temp_file}"; read -p "按回车返回..."; return
    fi
    if cmp -s "${SCRIPT_PATH}" "${temp_file}"; then
        echo -e "${C_GREEN}您当前已是最新版本。${C_RESET}"; rm -f "${temp_file}"
    else
        echo -e "${C_GREEN}发现新版本！正在自动更新...${C_RESET}"
        mv "${temp_file}" "${SCRIPT_PATH}"; chmod +x "${SCRIPT_PATH}"
        echo -e "${C_GREEN}更新成功！脚本将自动重启...${C_RESET}"; sleep 2
        exec bash "${SCRIPT_PATH}"
    fi
    read -p "按回车键返回主菜单..."
}

setup_script() {
    echo -e "${C_CYAN}=== SillyTavern 管理器首次设置 ===${C_RESET}"
    ensure_dirs; cp "$0" "${SCRIPT_PATH}"; chmod +x "${SCRIPT_PATH}"
    local bashrc_file="${HOME}/.bashrc"
    local start_command="bash ${SCRIPT_PATH}"
    if ! grep -qF "${start_command}" "${bashrc_file}"; then
        echo -e "\n# 自动启动 SillyTavern 管理器\n${start_command}" >> "${bashrc_file}"
        echo -e "${C_GREEN}已将脚本设置为 Termux 启动时自动运行。${C_RESET}"
    fi
    echo -e "${C_GREEN}设置完成！正在进入主菜单...${C_RESET}"; sleep 2
    exec bash "${SCRIPT_PATH}"
}

# --- 主菜单 ---
main_menu() {
    while true; do
        clear
        local st_version="未安装"
        local main_option_text
        local is_installed=false
        if [ -d "${ST_DIR}" ] && [ -f "${ST_DIR}/package.json" ]; then
            st_version=$(grep '"version":' "${ST_DIR}/package.json" | sed 's/.*: "\(.*\)".*/\1/')
            main_option_text="启动 SillyTavern"
            is_installed=true
        else
            main_option_text="安装 SillyTavern"
        fi

        echo -e "${C_BLUE}=======================================${C_RESET}"
        echo -e "${C_CYAN}        SillyTavern 管理器           ${C_RESET}"
        echo -e "${C_BLUE}=======================================${C_RESET}"
        echo -e "SillyTavern 版本: ${C_GREEN}${st_version}${C_RESET}\n"
        
        echo -e "  ${C_GREEN}0. ${main_option_text}${C_RESET} (默认选项, 直接回车)"
        echo "  1. 更新 SillyTavern"
        echo ""
        echo -e "${C_CYAN}--- 数据备份 ---${C_RESET}"
        load_backup_config
        if [ -f "${CONFIG_FILE}" ]; then
            echo -e "  状态: ${C_GREEN}已配置${C_RESET} | 保留 ${C_YELLOW}${BACKUP_DAYS}${C_RESET} 天 | 每天 ${C_YELLOW}${BACKUP_TIME}${C_RESET} 自动备份"
            echo "  2. 重新配置备份功能"
            echo "  3. 管理备份设置"
        else
            echo -e "  状态: ${C_RED}未配置${C_RESET}"
            echo "  2. 安装/配置备份功能"
        fi
        echo "  4. 立即手动备份一次"
        echo ""
        echo -e "${C_CYAN}--- 管理器 ---${C_RESET}"
        echo "  5. 更新管理器脚本"
        echo "  6. 退出脚本"
        echo -e "${C_BLUE}---------------------------------------${C_RESET}"
        
        read -p "请输入选项 (默认: 0): " choice
        choice=${choice:-0}

        case $choice in
            0) if $is_installed; then start_sillytavern; else install_sillytavern; fi ;;
            1) if $is_installed; then update_sillytavern; else echo -e "${C_RED}请先安装 SillyTavern (选项0)。${C_RESET}"; sleep 1; fi ;;
            2) if $is_installed; then setup_backup; read -p "按回车键返回。"; else echo -e "${C_RED}请先安装 SillyTavern (选项0)。${C_RESET}"; sleep 1; fi ;;
            3) if $is_installed && [ -f "${CONFIG_FILE}" ]; then manage_backup; else echo -e "${C_RED}请先安装SillyTavern并配置备份。${C_RESET}"; sleep 1; fi ;;
            4) if $is_installed; then manual_backup; else echo -e "${C_RED}请先安装 SillyTavern (选项0)。${C_RESET}"; sleep 1; fi ;;
            5) update_self ;;
            6) echo "退出脚本。"; exit 0 ;;
            *) echo -e "${C_RED}无效选项，请重试。${C_RESET}"; sleep 1 ;;
        esac
    done
}

# --- 脚本入口 ---
case "$1" in
    --run-backup) ensure_dirs; run_backup ;;
    *)
        if [ "$(realpath "$0")" != "${SCRIPT_PATH}" ]; then
            echo "首次运行，正在自动安装管理器..."
            setup_script
        else
            main_menu
        fi ;;
esac
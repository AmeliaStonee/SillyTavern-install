#!/data/data/com.termux/files/usr/bin/bash

# SillyTavern Manager by AmeliaStonee's request
# Version 1.1

# --- 配置 ---
# SillyTavern 安装目录 (相对于 HOME)
ST_DIR_NAME="SillyTavern"
ST_DIR="${HOME}/${ST_DIR_NAME}"

# SillyTavern 用户数据子路径 (用于备份)
ST_DATA_USER_SUBPATH="data/default-user"

# 脚本和配置文件的存放位置
SCRIPT_INSTALL_DIR="${HOME}/.st-manager"
SCRIPT_PATH="${SCRIPT_INSTALL_DIR}/st-manager.sh"
CONFIG_FILE="${SCRIPT_INSTALL_DIR}/config.conf"
LOG_FILE="${SCRIPT_INSTALL_DIR}/backup.log"

# 脚本的 GitHub 源 URL (用于自我更新)
SCRIPT_URL="https://raw.githubusercontent.com/AmeliaStonee/SillyTavern-install/main/st-manager.sh"

# --- 颜色定义 ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'

# --- 辅助函数 ---
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "${LOG_FILE}"
}

ensure_dirs() {
    mkdir -p "${SCRIPT_INSTALL_DIR}"
}

# --- 核心功能函数 ---

# 1. 安装 SillyTavern
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
    read -p "您想安装哪个分支？[1] main (稳定版) [2] staging (开发版, 默认): " branch_choice
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

# 2. 启动 SillyTavern
start_sillytavern() {
    # ... (此函数无需修改)
    echo -e "${C_CYAN}=== 启动 SillyTavern ===${C_RESET}"
    
    if [ -f "$CONFIG_FILE" ]; then
        if ! pgrep -f "crond" > /dev/null; then
            echo -e "${C_YELLOW}警告：检测到备份已配置，但定时服务 (crond) 未运行。${C_RESET}"
            read -p "是否现在启动它？[Y/n]: " start_cron
            start_cron=${start_cron:-Y}
            if [[ "$start_cron" =~ ^[Yy]$ ]]; then
                crond
                echo -e "${C_GREEN}定时服务已启动。${C_RESET}"
            else
                echo -e "${C_RED}备份服务未启动，自动备份将不会执行。${C_RESET}"
            fi
        else
             echo -e "${C_GREEN}备份服务正常运行中。${C_RESET}"
        fi
    else
        echo -e "${C_YELLOW}警告：您尚未配置自动备份功能。${C_RESET}"
        read -p "强烈建议现在配置，是否继续？[Y/n]: " config_backup
        config_backup=${config_backup:-Y}
        if [[ "$config_backup" =~ ^[Yy]$ ]]; then
            setup_backup
            if ! pgrep -f "crond" > /dev/null; then
                crond
            fi
        else
            echo -e "${C_RED}已跳过备份配置。请注意数据安全。${C_RESET}"
        fi
    fi

    echo -e "${C_CYAN}正在进入 SillyTavern 目录并执行 start.sh...${C_RESET}"
    cd "${ST_DIR}" || { echo -e "${C_RED}错误: 无法进入目录 ${ST_DIR}${C_RESET}"; exit 1; }
    bash start.sh
}

# 3. 更新 SillyTavern
update_sillytavern() {
    # ... (此函数无需修改)
    echo -e "${C_CYAN}=== 更新 SillyTavern ===${C_RESET}"
    cd "${ST_DIR}" || { echo -e "${C_RED}错误: 找不到 SillyTavern 目录。${C_RESET}"; return; }
    
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    echo -e "当前所在分支: ${C_GREEN}${current_branch}${C_RESET}"

    echo "请选择操作:"
    echo "1. 拉取当前分支的最新更新 (git pull)"
    echo "2. 切换到其他分支 (main/staging)"
    echo "0. 返回"
    read -p "请输入选项: " update_choice

    case $update_choice in
        1)
            echo -e "${C_YELLOW}正在拉取更新...${C_RESET}"
            git pull
            echo -e "${C_YELLOW}正在重新安装依赖...${C_RESET}"
            npm install
            echo -e "${C_GREEN}更新完成！${C_RESET}"
            ;;
        2)
            echo "选择要切换到的分支:"
            echo "1. main (稳定版)"
            echo "2. staging (开发版)"
            read -p "请输入选项: " branch_switch_choice
            case $branch_switch_choice in
                1) git switch main && git pull && npm install && echo -e "${C_GREEN}已切换到 main 分支并更新。${C_RESET}" ;;
                2) git switch staging && git pull && npm install && echo -e "${C_GREEN}已切换到 staging 分支并更新。${C_RESET}" ;;
                *) echo -e "${C_RED}无效选项。${C_RESET}" ;;
            esac
            ;;
        0) return ;;
        *) echo -e "${C_RED}无效选项。${C_RESET}" ;;
    esac
    read -p "按回车键返回主菜单..."
}

# --- 备份相关函数 ---

# 读取备份配置
load_backup_config() {
    if [ -f "${CONFIG_FILE}" ]; then
        source "${CONFIG_FILE}"
    else
        BACKUP_DIR=""
        BACKUP_DAYS=""
        BACKUP_TIME=""
    fi
}

# 执行一次备份 (已按新要求重写)
run_backup() {
    load_backup_config
    if [ -z "${BACKUP_DIR}" ] || [ -z "${BACKUP_DAYS}" ]; then
        log "备份失败：备份未配置。"
        return 1
    fi

    local data_dir="${ST_DIR}/${ST_DATA_USER_SUBPATH}"
    if [ ! -d "${data_dir}" ]; then
        log "备份失败：找不到数据目录 ${data_dir}"
        return 1
    fi
    
    mkdir -p "${BACKUP_DIR}"
    
    local timestamp
    timestamp=$(date +%Y%m%d)
    local filename="SillyTavern-${timestamp}.zip"
    
    log "开始备份到 ${BACKUP_DIR}/${filename}"
    
    # 获取数据文件夹的父目录和它本身的名字
    local parent_dir
    parent_dir=$(dirname "${data_dir}")
    local user_data_folder
    user_data_folder=$(basename "${data_dir}")

    # 使用 pushd/popd 切换目录来确保 zip 内部结构正确
    pushd "${parent_dir}" > /dev/null
    zip -r "${BACKUP_DIR}/${filename}" "${user_data_folder}"
    local zip_status=$?
    popd > /dev/null
    
    if [ ${zip_status} -eq 0 ]; then
        log "备份成功创建：${filename}"
    else
        log "备份失败：zip 命令出错。"
        return 1
    fi

    log "开始清理 ${BACKUP_DAYS} 天前的旧备份..."
    find "${BACKUP_DIR}" -name "SillyTavern-*.zip" -mtime +"${BACKUP_DAYS}" -exec rm {} \;
    log "清理完成。"
    return 0
}


# 4. 设置/安装备份功能 (已修改默认目录)
setup_backup() {
    echo -e "${C_CYAN}=== 配置自动备份 ===${C_RESET}"
    
    echo "备份功能会将您的角色、聊天记录等核心数据打包压缩。"
    
    # 询问备份目录
    default_backup_dir="/storage/BA73-022B/backups/"
    echo -e "请输入备份文件存放的目录路径。"
    echo -e "${C_YELLOW}警告：默认路径是一个SD卡路径，可能在您的设备上无效。${C_RESET}"
    read -p "备份目录 (默认: ${default_backup_dir}): " backup_dir
    BACKUP_DIR=${backup_dir:-${default_backup_dir}}
    
    read -p "您想保留最近多少天的备份？ (默认: 7): " backup_days
    BACKUP_DAYS=${backup_days:-7}
    
    read -p "设置每天自动备份的时间 (24小时制, 例如 03:00): " backup_time
    BACKUP_TIME=${backup_time:-03:00}

    mkdir -p "${SCRIPT_INSTALL_DIR}"
    echo "BACKUP_DIR=\"${BACKUP_DIR}\"" > "${CONFIG_FILE}"
    echo "BACKUP_DAYS=\"${BACKUP_DAYS}\"" >> "${CONFIG_FILE}"
    echo "BACKUP_TIME=\"${BACKUP_TIME}\"" >> "${CONFIG_FILE}"

    echo -e "${C_GREEN}备份配置已保存。${C_RESET}"

    install_cron_job
}

# 安装或更新 cron 任务
install_cron_job() {
    # ... (此函数无需修改)
    load_backup_config
    if [ -z "${BACKUP_TIME}" ]; then
        echo -e "${C_RED}错误: 备份时间未设置，无法创建定时任务。${C_RESET}"; return
    fi

    local minute hour
    minute=$(echo "$BACKUP_TIME" | cut -d: -f2)
    hour=$(echo "$BACKUP_TIME" | cut -d: -f1)
    
    if ! command -v crond &> /dev/null; then
        echo -e "${C_YELLOW}正在安装 cronie (定时任务服务)...${C_RESET}"; pkg install cronie -y
    fi

    local cron_job="${minute} ${hour} * * * ${SCRIPT_PATH} --run-backup"
    (crontab -l 2>/dev/null | grep -v "${SCRIPT_PATH}") | { cat; echo "${cron_job}"; } | crontab -
    
    echo -e "${C_GREEN}自动备份任务已设置为每天 ${BACKUP_TIME} 执行。${C_RESET}"
    
    if ! pgrep -f "crond" > /dev/null; then
        crond; echo -e "${C_GREEN}定时服务 (crond) 已启动。${C_RESET}"
    fi
}

# 5. 管理备份功能
manage_backup() {
    # ... (此函数无需修改)
    while true; do
        clear
        load_backup_config
        echo -e "${C_CYAN}=== 管理备份设置 ===${C_RESET}"
        echo -e "当前设置:\n  备份目录: ${C_GREEN}${BACKUP_DIR}${C_RESET}\n  保留天数: ${C_GREEN}${BACKUP_DAYS}${C_RESET}\n  自动备份时间: ${C_GREEN}${BACKUP_TIME}${C_RESET}"
        echo "------------------------"
        echo "1. 修改自动备份的时间"; echo "2. 修改自动备份数据的天数"; echo "3. 修改备份文件夹目录"; echo "0. 返回主菜单"
        read -p "请输入选项: " choice

        case $choice in
            1)
                read -p "输入新的自动备份时间 (例如 03:00): " new_time
                if [[ "$new_time" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
                    sed -i "s|BACKUP_TIME=.*|BACKUP_TIME=\"${new_time}\"|" "${CONFIG_FILE}" && install_cron_job && echo -e "${C_GREEN}时间已更新。${C_RESET}"
                else
                    echo -e "${C_RED}格式错误。${C_RESET}"
                fi; sleep 1 ;;
            2)
                read -p "输入新的保留天数 (例如 7): " new_days
                if [[ "$new_days" =~ ^[0-9]+$ ]]; then
                    sed -i "s|BACKUP_DAYS=.*|BACKUP_DAYS=\"${new_days}\"|" "${CONFIG_FILE}" && echo -e "${C_GREEN}保留天数已更新。${C_RESET}"
                else
                    echo -e "${C_RED}请输入一个数字。${C_RESET}"
                fi; sleep 1 ;;
            3)
                read -p "输入新的备份目录: " new_dir
                sed -i "s|BACKUP_DIR=.*|BACKUP_DIR=\"${new_dir}\"|" "${CONFIG_FILE}" && echo -e "${C_GREEN}备份目录已更新。${C_RESET}"
                sleep 1 ;;
            0) break ;;
            *) echo -e "${C_RED}无效选项。${C_RESET}"; sleep 1 ;;
        esac
    done
}

# 6. 手动备份
manual_backup() {
    # ... (此函数无需修改)
    echo -e "${C_CYAN}=== 手动备份 ===${C_RESET}"
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo -e "${C_YELLOW}您尚未配置备份，请先配置。${C_RESET}"; setup_backup
    fi
    echo -e "${C_YELLOW}正在执行备份...${C_RESET}"
    if run_backup; then
        echo -e "${C_GREEN}手动备份成功！${C_RESET}"
    else
        echo -e "${C_RED}手动备份失败，请检查日志: ${LOG_FILE}${C_RESET}"
    fi
    read -p "按回车键返回主菜单..."
}

# --- 新增：脚本自我更新功能 ---
update_self() {
    echo -e "${C_CYAN}=== 检查管理器脚本更新 ===${C_RESET}"
    local temp_file
    temp_file=$(mktemp)
    
    echo -e "${C_YELLOW}正在从 GitHub 下载最新版本...${C_RESET}"
    if ! wget -q -O "${temp_file}" "${SCRIPT_URL}"; then
        echo -e "${C_RED}下载失败，请检查网络连接。${C_RESET}"
        rm -f "${temp_file}"
        read -p "按回车键返回..."
        return
    fi

    # -s 选项使 cmp 在文件相同时静默
    if cmp -s "${SCRIPT_PATH}" "${temp_file}"; then
        echo -e "${C_GREEN}您当前已是最新版本。${C_RESET}"
        rm -f "${temp_file}"
    else
        echo -e "${C_GREEN}发现新版本！${C_RESET}"
        read -p "是否要更新管理器脚本？[Y/n]: " confirm_update
        confirm_update=${confirm_update:-Y}
        if [[ "${confirm_update}" =~ ^[Yy]$ ]]; then
            # 覆盖旧脚本
            mv "${temp_file}" "${SCRIPT_PATH}"
            chmod +x "${SCRIPT_PATH}"
            echo -e "${C_GREEN}更新成功！脚本将自动重启以应用更新...${C_RESET}"
            sleep 2
            exec bash "${SCRIPT_PATH}" # 重启脚本
        else
            echo "已取消更新。"
            rm -f "${temp_file}"
        fi
    fi
    read -p "按回车键返回主菜单..."
}


# --- 脚本自安装与设置 ---
setup_script() {
    # ... (此函数无需修改)
    echo -e "${C_CYAN}=== SillyTavern 管理器首次设置 ===${C_RESET}"
    ensure_dirs
    
    cp "$0" "${SCRIPT_PATH}"
    chmod +x "${SCRIPT_PATH}"
    
    local bashrc_file="${HOME}/.bashrc"
    local start_command="bash ${SCRIPT_PATH}"
    
    if ! grep -qF "${start_command}" "${bashrc_file}"; then
        echo -e "\n# 自动启动 SillyTavern 管理器\n${start_command}" >> "${bashrc_file}"
        echo -e "${C_GREEN}已将脚本设置为 Termux 启动时自动运行。${C_RESET}"
    else
        echo -e "${C_YELLOW}脚本已配置为自动运行。${C_RESET}"
    fi
    
    echo -e "${C_GREEN}设置完成！脚本现在位于 ${SCRIPT_PATH}${C_RESET}"
    echo "正在进入主菜单..."
    sleep 2
    exec bash "${SCRIPT_PATH}"
}

# --- 主菜单 (已更新) ---
main_menu() {
    while true; do
        clear
        local st_version="未安装"
        local main_option_text="安装 SillyTavern"
        local main_option_num=1
        
        if [ -d "${ST_DIR}" ] && [ -f "${ST_DIR}/package.json" ]; then
            st_version=$(grep '"version":' "${ST_DIR}/package.json" | sed 's/.*: "\(.*\)".*/\1/')
            main_option_text="启动 SillyTavern"
            main_option_num=0
        fi

        echo -e "${C_BLUE}=======================================${C_RESET}"
        echo -e "${C_CYAN}        SillyTavern 管理器           ${C_RESET}"
        echo -e "${C_BLUE}=======================================${C_RESET}"
        echo -e "SillyTavern 版本: ${C_GREEN}${st_version}${C_RESET}"
        echo ""

        if [ "$main_option_num" -eq 0 ]; then
             echo -e "  ${C_GREEN}0. ${main_option_text}${C_RESET} (默认选项, 直接回车)"
        else
             echo -e "  ${C_YELLOW}1. ${main_option_text}${C_RESET}"
        fi
        
        echo "  2. 更新 SillyTavern"
        echo ""
        echo -e "${C_CYAN}--- 数据备份 ---${C_RESET}"
        load_backup_config
        if [ -f "${CONFIG_FILE}" ]; then
            echo -e "  状态: ${C_GREEN}已配置${C_RESET} | 保留 ${C_YELLOW}${BACKUP_DAYS}${C_RESET} 天 | 每天 ${C_YELLOW}${BACKUP_TIME}${C_RESET} 自动备份"
            echo "  3. 重新配置备份功能"
            echo "  4. 管理备份设置"
        else
            echo -e "  状态: ${C_RED}未配置${C_RESET}"
            echo "  3. 安装/配置备份功能"
        fi
        echo "  5. 立即手动备份一次"
        echo ""
        echo -e "${C_CYAN}--- 管理器 ---${C_RESET}"
        echo "  8. 更新管理器脚本"
        echo "  9. 退出脚本"
        
        echo -e "${C_BLUE}---------------------------------------${C_RESET}"
        
        read -p "请输入选项 (默认: ${main_option_num:-1}): " choice
        choice=${choice:-$main_option_num}

        case $choice in
            0) 
                if [ "$main_option_num" -eq 0 ]; then start_sillytavern; else echo -e "${C_RED}无效选项。${C_RESET}"; sleep 1; fi ;;
            1) 
                if [ "$main_option_num" -eq 1 ]; then install_sillytavern; else echo -e "${C_RED}无效选项，SillyTavern 已安装。请选择 0 启动。${C_RESET}"; sleep 1; fi ;;
            2) update_sillytavern ;;
            3) setup_backup; read -p "按回车键返回主菜单..." ;;
            4) if [ -f "${CONFIG_FILE}" ]; then manage_backup; else echo -e "${C_RED}请先配置备份功能 (选项3)。${C_RESET}"; sleep 1; fi ;;
            5) manual_backup ;;
            8) update_self ;;
            9) echo "退出脚本。"; exit 0 ;;
            *) echo -e "${C_RED}无效选项，请重试。${C_RESET}"; sleep 1 ;;
        esac
    done
}


# --- 脚本入口 ---
case "$1" in
    --setup) setup_script ;;
    --run-backup) ensure_dirs; run_backup ;;
    *)
        if [ "$(realpath "$0")" != "${SCRIPT_PATH}" ]; then
            echo "检测到脚本在临时位置运行。"
            read -p "是否将此脚本安装到系统中并设置为自动启动? [Y/n]: " setup_confirm
            setup_confirm=${setup_confirm:-Y}
            if [[ "$setup_confirm" =~ ^[Yy]$ ]]; then setup_script; else echo "已取消安装。脚本将在临时模式下运行一次。"; main_menu; fi
        else
            main_menu
        fi ;;
esac
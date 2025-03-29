#!/bin/bash
#
# Starts a remote sbatch jobs and sets up correct port forwarding.
# Sample usage: bash start.sh sherlock/singularity-jupyter 
#               bash start.sh sherlock/singularity-jupyter /home/users/raphtown
#               bash start.sh sherlock/singularity-jupyter /home/users/raphtown

# -----------------------------------------------------------------------------
# 读取配置文件
# -----------------------------------------------------------------------------
# 检查是否存在配置文件 params.sh
if [ ! -f params.sh ]
then
    echo "Need to configure params before first run, run setup.sh!"
    exit
fi
# 加载配置
. params.sh

# -----------------------------------------------------------------------------
# 定义帮助信息
# -----------------------------------------------------------------------------
function show_help() {
  echo "Usage: bash start.sh JOB_NAME [options]"
  echo ""
  echo "Options:"
  echo "  -p PARTITION    Slurm partition to use (e.g., gpu, normal, owners)"
  echo "                  → 'gpu' will trigger GPU allocation"
  echo ""
  echo "  -g GPUS         Number of GPUs to request (e.g., 1, 2)"
  echo "                  → Only meaningful when -p gpu"
  echo ""
  echo "  -c CPUS         Number of CPUs to request (e.g., 4, 8, 16)"
  echo "  -m MEM          Memory to allocate (e.g., 16G, 32G)"
  echo "  -t TIME         Max run time (e.g., 02:00:00 for 2 hours)"
  echo "  -f PORT         Local port to forward (e.g., 8888)"
  echo "  -h              Show this help message and exit"
  echo ""
  echo "Example:"
  echo "  bash start.sh py12torch2 -p xiaojie -g 2 -c 32 -m 32G -t 04:00:00 -f 17173"
  echo ""
  exit 0
}

# -----------------------------------------------------------------------------
# 配置参数检查和辅助函数加载
# -----------------------------------------------------------------------------
# 解析命令行参数（getopts 放在这里）
while getopts ":p:m:t:f:c:g:h" opt; do
  case $opt in
    p) PARTITION="$OPTARG" ;;
    m) MEM="$OPTARG" ;;
    t) TIME="$OPTARG" ;;
    f) PORT="$OPTARG" ;;
    c) CPUS="$OPTARG" ;;
    g) GPUS="$OPTARG" ;;
    h) show_help ;;
    \?) echo "Invalid option: -$OPTARG" >&2; show_help ;;
    :) echo "Option -$OPTARG requires an argument." >&2; show_help ;;
  esac
done
shift $((OPTIND - 1))  # 移除已处理参数，保留 JOB_NAME 等位置参数

# 确保调用脚本时至少提供了一个 sbatch job 名。
if [ "$#" -eq 0 ]
then
    echo "Need to give name of sbatch job to run!"
    show_help
    exit
fi

# 加载辅助函数
if [ ! -f helpers.sh ]
then
    echo "Cannot find helpers.sh script!"
    exit
fi
. helpers.sh

# 功能糖：支持任务只输入job名，可不加.sbatch后缀
NAME="${1:-}"

# The user could request either <resource>/<script>.sbatch or
#                               <name>.sbatch
SBATCH="$NAME.sbatch"

# 智能查找目标 sbatch 脚本
set_forward_script

# 检查是否已有相同$NAME的 job 在运行，防止端口冲突资源浪费
check_previous_submit

# -----------------------------------------------------------------------------
# 在远程集群（比如 Sherlock）上准备运行环境
# -----------------------------------------------------------------------------
# 🔹 第一步：获取远程主目录，创建日志目录forward-util（如无）
echo
echo "== Getting destination directory =="
RESOURCE_HOME=`ssh ${RESOURCE} pwd`
ssh ${RESOURCE} mkdir -p $RESOURCE_HOME/forward-util

# 第二步：上传要运行的 sbatch 脚本
echo
echo "== Uploading sbatch script =="
scp $FORWARD_SCRIPT ${RESOURCE}:$RESOURCE_HOME/forward-util/

# 处理GPU申请，如果PARTITION=gpu， 补全为--partition=gpu --gres=gpu:1 
# adjust PARTITION if necessary
set_partition
echo

# -----------------------------------------------------------------------------
# 在远程运行sbatch命令，向集群提交计算任务
# -----------------------------------------------------------------------------

echo "== Submitting sbatch =="

SBATCH_NAME=$(basename $SBATCH)
command="sbatch
    --job-name=$NAME
    --partition=$PARTITION
    --output=$RESOURCE_HOME/forward-util/$SBATCH_NAME.out
    --error=$RESOURCE_HOME/forward-util/$SBATCH_NAME.err
    --mem=$MEM
    --time=$TIME
    $RESOURCE_HOME/forward-util/$SBATCH_NAME $PORT \"${@:2}\""

echo ${command}
ssh ${RESOURCE} ${command}

# Tell the user how to debug before trying | 提示日志位置
instruction_get_logs

# -----------------------------------------------------------------------------
# 等待运行并打SSH隧道
# -----------------------------------------------------------------------------
# Wait for the node allocation, get identifier
# 这个函数自动帮你 “等到任务真的启动了”，并把它运行在哪台计算节点上找出来，用于打隧道
get_machine
echo "notebook running on $MACHINE"
sleep $CONNECTION_WAIT_SECONDS

# Sherlock 上有些计算节点无法从你本地机直接访问（被隔离在集群内部），此时你要做 双跳 SSH
# 第一跳：从你本地连接 RESOURCE（如 login node）
# 第二跳：由 login node 再连接 MACHINE（实际运行 notebook 的节点）（如果可以直连则不必执行）
# 每一跳都做一次本地端口转发
# 📌 结果：
# 你访问 localhost:$PORT → 实际等于访问 $MACHINE:$PORT。
setup_port_forwarding

echo "== Connecting to notebook =="

# Print logs for the user, in case needed
print_logs

echo
instruction_get_logs

echo 
echo "== Instructions =="
echo "1. Password, output, and error printed to this terminal? Look at logs (see instruction above)"
echo "2. Browser: http://$MACHINE:$PORT/ -> http://localhost:$PORT/..."
echo "3. To end session: bash end.sh ${NAME}"


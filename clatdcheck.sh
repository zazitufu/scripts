### 此脚本用来检查clatd这个服务是否正常运行，如果不能正常运行，就重启这个服务
##  用在scaleway 的stardust 纯ipv6服务器上，通过clatd的服务来获取ipv4，但是经常会用着用着就没了ipv4，于是用这个脚本来保障
##  思路是通过curl -4 Google，如果一定时间内没有返回值，则判断clatd失效了，需要重启。
##  2023年3月13日
#!/bin/bash

service_name="clatd.service"
log_file="/aalog/clatd.log"

# 记录日志函数
function log {
    message=$1
    echo "$(date '+%Z %Y-%m-%d %H:%M:%S') $message" >> $log_file
}

# 重启服务函数
function restart_service {
    systemctl restart $service_name
    log "Restarted $service_name"
}

# 判断服务是否正常运行
function check_service {
    response=$(curl --connect-timeout 8 -4 google.com > /dev/null 2>&1)
    if [ $? -eq 0 ]; then
#        log "Service is running normally"
        return 0
    else
        log "Service is down"
        return 1
    fi
}

# 主循环
while true
do
    if check_service; then
        # 如果服务正常，删除log文件中最后一次成功的记录
        sed -i '${/Service is running normally/d;}' $log_file
        log "Service is running normally"

    else
        restart_service
        sleep 60
        if check_service; then
            log "Service restarted"
        else
            # 重启服务5次都无法成功，重启实例
            for i in {1..5}
            do
                restart_service
                sleep 60
                if check_service; then
                    log "Service restarted"
                    break
                fi
            done
            # 重启5次还是失败，重启实例
            if [ $i -eq 5 ]; then
                log "Failed to restart service, rebooting instance"
                reboot
            fi
        fi
    fi
    sleep 30
done

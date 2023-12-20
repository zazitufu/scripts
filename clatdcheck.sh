### 此脚本用来检查clatd这个服务是否正常运行，如果不能正常运行，就重启这个服务
##  用在scaleway 的stardust 纯ipv6服务器上，通过clatd的服务来获取ipv4，但是经常会用着用着就没了ipv4，于是用这个脚本来保障，配合clatdcheck.service服务来调用。
##  思路是通过curl -4 Google，如果一定时间内没有返回值，则判断clatd失效了，需要重启。
##  找一大轮无法实现reboot后，禁止每隔一段时间自动添加default route，编辑/etc/systemd/network/ 下面的.network，添加UseRoutes=false无效，只能改/run 下面的文件才生效。
##  2023年12月20日
#!/bin/bash

service_name="clatd.service"
log_file="/aalog/clatd.log"
## /run/systemd/network/10-netplan-eth0.network 根据不同机子可能不同文件名。
network_config="/run/systemd/network/10-netplan-eth0.network"

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

# 检查并修改网络配置
function check_and_modify_network_config {
    if grep -q "\[DHCP\]" $network_config; then
        if ! grep -q "UseRoutes=false" $network_config; then
            sed -i '/\[DHCP\]/a UseRoutes=false' $network_config
            systemctl restart systemd-networkd
            log "Modified network config and restarted systemd-networkd"
        fi
    fi
}

# 判断服务是否正常运行
function check_service {
    response=$(curl --connect-timeout 8 -4 google.com > /dev/null 2>&1)
    if [ $? -eq 0 ]; then
        # log "Service is running normally"
        return 0
    else
        log "Service is down"
        return 1
    fi
}

# 主循环
while true
do
    check_and_modify_network_config

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

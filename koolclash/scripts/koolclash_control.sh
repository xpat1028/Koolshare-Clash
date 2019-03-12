#!/bin/sh

export KSROOT=/koolshare
source $KSROOT/scripts/base.sh
eval $(dbus export koolclash_)
alias echo_date='echo 【$(date +%Y年%m月%d日\ %X)】:'

NAME=clash
PIDFILE=/var/run/$NAME.pid
#This is the command to be run, give the full pathname
DAEMON=/usr/local/bin/bar
DAEMON_OPTS="-d $KSROOT/koolclash/config/"

#--------------------------------------------------------------------------
restore_dnsmasq_conf() {
    # delete server setting in dnsmasq.conf
    #pc_delete "server=" "/etc/dnsmasq.conf"
    #pc_delete "all-servers" "/etc/dnsmasq.conf"
    #pc_delete "no-resolv" "/etc/dnsmasq.conf"
    #pc_delete "no-poll" "/etc/dnsmasq.conf"

    echo_date "删除 KoolClash 的 dnsmasq 配置..."
    #rm -rf /tmp/dnsmasq.d/koolclash.conf
}

restore_start_file() {
    echo_date "删除 KoolClash 的防火墙配置"

    uci -q batch <<-EOT
	  delete firewall.ks_koolclash
	  commit firewall
	EOT
}

kill_process() {
    # 关闭 Clash 进程
    if [ -n "$(pidof clash)" ]; then
        echo_date "关闭 Clash 进程..."
        killall clash
    fi
}

create_dnsmasq_conf() {
    touch /tmp/dnsmasq.d/koolclash.conf

    echo "no-resolv" >>/tmp/dnsmasq.d/koolclash.conf
    echo "server=127.0.0.1# 23453" >>/tmp/dnsmasq.d/koolclash.conf
}

restart_dnsmasq() {
    # Restart dnsmasq
    echo_date 重启dnsmasq服务...
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
}

#--------------------------------------------------------------------------------------
auto_start() {
    # nat start
    echo_date "添加 KoolClash 防火墙规则"
    uci -q batch <<-EOT
	  delete firewall.ks_koolclash
	  set firewall.ks_koolclash=include
	  set firewall.ks_koolclash.type=script
	  set firewall.ks_koolclash.path=/koolshare/scripts/koolclash_control.sh
	  set firewall.ks_koolclash.family=any
	  set firewall.ks_koolclash.reload=1
	  commit firewall
	EOT

    [ ! -L "/etc/rc.d/S99koolclash.sh" ] && ln -sf $KSROOT/init.d/S99koolclash.sh /etc/rc.d/S99koolclash.sh
}

#--------------------------------------------------------------------------------------
start_clash_process() {
    echo_date "启动 Clash"
    start-stop-daemon -S -q -b -m \
        -p /tmp/run/koolclash.pid \
        -x /koolshare/bin/clash \
        -- -d $KSROOT/koolclash/config/
}

#--------------------------------------------------------------------------
flush_nat() {
    echo_date "尝试先清除已存在的iptables规则，防止重复添加"
    # flush iptables rules
    iptables -t nat -F koolclash
    iptables -t nat -X koolclash

    #chromecast_nu=$(iptables -t nat -L PREROUTING -v -n --line-numbers | grep "dpt:53" | awk '{print $1}')
    #[ $(dbus get koolproxy_enable) -ne 1 ] && iptables -t nat -D PREROUTING $chromecast_nu >/dev/null 2>&1
}

#--------------------------------------------------------------------------
apply_nat_rules() {
    #----------------------BASIC RULES---------------------
    echo_date "写入 iptables 规则"
    #-------------------------------------------------------
    # 局域网黑名单（不走ss）/局域网黑名单（走ss）
    # lan_acess_control
    # 其余主机默认模式
    # iptables -t mangle -A koolclash -j $(get_action_chain $ss_acl_default_mode)
    # 重定所有流量到透明代理端口
    iptables -t nat -N koolclash
    iptables -t nat -A koolclash -p tcp --dport 22 -j ACCEPT
    iptables -t nat -A koolclash -p tcp -j REDIRECT --to-ports 23456
    iptables -t nat -I OUTPUT -p tcp -j koolclash
}

# =======================================================================================================
load_nat() {
    echo_date "开始加载 nat 规则!"
    #flush_nat
    #creat_ipset
    apply_nat_rules
    #chromecast
}

start_koolclash() {
    # get_status >> /tmp/ss_start.txt
    # used by web for start/restart; or by system for startup by S99koolss.sh in rc.d
    echo_date -------------------- KoolClash: Clash on Koolshare OpenWrt ----------------------------
    [ -n "$ONSTART" ] && echo_date 路由器开机触发 KoolClash 启动！ || echo_date web 提交操作触发 KoolClash 启动！
    echo_date ---------------------------------------------------------------------------------------
    # stop first
    #restore_dnsmasq_conf
    flush_nat
    restore_start_file
    kill_process
    echo_date ---------------------------------------------------------------------------------------
    #create_dnsmasq_conf
    auto_start
    start_clash_process
    load_nat
    restart_dnsmasq
    echo_date ------------------------- KoolClash 启动完毕 -------------------------
}

stop_koolclash() {
    echo_date -------------------- KoolClash: Clash on Koolshare OpenWrt ----------------------------
    #restore_dnsmasq_conf
    restart_dnsmasq
    flush_nat
    restore_start_file
    kill_process
    echo_date ------------------------- KoolClash 停止完毕 -------------------------
}

# used by rc.d and firewall include
case $1 in
start)
    if [ "$koolclash_enable" == "1" ]; then
        if [ ! -f $KSROOT/koolclash/config/config.yml ]; then
            echo_date "没有配置文件！"
            stop_koolclash
        else
            if [ $(yq r $KSROOT/koolclash/config/config.yml dns.enable) == 'true' ] && [ $(yq r $KSROOT/koolclash/config/config.yml dns.enhanced-mode) == 'redir-host' ]; then
                start_koolclash
            else
                echo_date "DNS 配置不合法！"
                stop_koolclash
            fi
        fi
    else
        echo_date "DNS 配置不合法！"
        stop_koolclash
    fi
    ;;
stop)
    stop_koolclash
    ;;
*)
    if [ -z "$2" ]; then
        #    if [ ! -f $KSROOT/koolclash/config/config.yml ]; then
        #        stop_koolclash
        #    else
        #        if [ $(yq r $KSROOT/koolclash/config/config.yml dns.enable) == 'true' ] && [ $(yq r $KSROOT/koolclash/config/config.yml dns.enhanced-mode) == 'redir-host' ]; then
        #            start_koolclash
        #        else
        #            stop_koolclash
        #        fi
        #    fi
        echo_date "Hello KoolClash"
    fi

    ;;
esac

# used by httpdb
case $2 in
start)
    if [ ! -f $KSROOT/koolclash/config/config.yml ]; then
        stop_koolclash
        http_response 'noconfig'
    else
        if [ $(yq r $KSROOT/koolclash/config/config.yml dns.enable) == 'true' ] && [ $(yq r $KSROOT/koolclash/config/config.yml dns.enhanced-mode) == 'redir-host' ]; then
            start_koolclash
            http_response 'success'
        else
            stop_koolclash
            http_response 'nodns'
        fi
    fi
    ;;
stop)
    stop_koolclash
    http_response 'success'
    ;;
esac

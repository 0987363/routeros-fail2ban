{
    :if ([:len [/system script find where name="LoginGuard"]] > 0) do={
        :error "LoginGuard:script-exists"
    }
    :if ([:len [/system logging action find where name="LoginGuardAction"]] > 0) do={
        :error "LoginGuard:action-exists"
    }
    :if ([:len [/ip firewall filter find where comment="LoginGuard:input-drop"]] > 0) do={
        :error "LoginGuard:rule-exists"
    }
    :if ([:len [/ip firewall address-list find where list="LoginGuardCount"]] > 0) do={
        :error "LoginGuard:counter-state-exists"
    }

    /system script add name=LoginGuard policy=read,write,test dont-require-permissions=no source={
        :onerror handlerError in={
            :local failureWindow 5m
            :local failureLimit 4
            :local banTime 1d

            :local msg $message
            :local prefix "login failure for user "
            :if ([:typeof $msg] != "str") do={ :return 0 }
            :if ([:pick $msg 0 [:len $prefix]] != $prefix) do={ :return 0 }

            :local lastFrom -1
            :local nextFrom [:find $msg " from "]
            :while ([:typeof $nextFrom] = "num") do={
                :set lastFrom $nextFrom
                :set nextFrom [:find $msg " from " $lastFrom]
            }
            :if ($lastFrom < [:len $prefix]) do={ :return 0 }
            :local viaAt [:find $msg " via " $lastFrom]
            :if ([:typeof $viaAt] != "num") do={ :return 0 }
            :local serviceName [:pick $msg ($viaAt + 5) [:len $msg]]
            :if ([:len $serviceName] = 0) do={ :return 0 }

            :local srcText [:pick $msg ($lastFrom + 6) $viaAt]
            :local srcIP [:toip $srcText]
            :if ([:typeof $srcIP] != "ip") do={ :return 0 }
            :if ([:tostr $srcIP] != $srcText) do={ :return 0 }

            :if ($srcIP in 0.0.0.0/8) do={ :return 0 }
            :if ($srcIP in 10.0.0.0/8) do={ :return 0 }
            :if ($srcIP in 100.64.0.0/10) do={ :return 0 }
            :if ($srcIP in 127.0.0.0/8) do={ :return 0 }
            :if ($srcIP in 169.254.0.0/16) do={ :return 0 }
            :if ($srcIP in 172.16.0.0/12) do={ :return 0 }
            :if ($srcIP in 192.0.0.0/24) do={ :return 0 }
            :if ($srcIP in 192.0.2.0/24) do={ :return 0 }
            :if ($srcIP in 192.88.99.0/24) do={ :return 0 }
            :if ($srcIP in 192.168.0.0/16) do={ :return 0 }
            :if ($srcIP in 198.18.0.0/15) do={ :return 0 }
            :if ($srcIP in 198.51.100.0/24) do={ :return 0 }
            :if ($srcIP in 203.0.113.0/24) do={ :return 0 }
            :if ($srcIP in 224.0.0.0/4) do={ :return 0 }
            :if ($srcIP in 240.0.0.0/4) do={ :return 0 }

            :if ([:len [/ip firewall address-list find where list="LoginGuardAllow" and address=$srcText and disabled=no]] > 0) do={
                :return 0
            }
            :if ([:len [/ip firewall address-list find where list="BLOCK" and address=$srcText and disabled=no]] > 0) do={
                :return 0
            }

            :local counterEntry [/ip firewall address-list find where list="LoginGuardCount" and address=$srcText]
            :local failures 1
            :if ([:len $counterEntry] > 0) do={
                :local previous [:tonum [/ip firewall address-list get $counterEntry comment]]
                :if ([:typeof $previous] != "num") do={ :error "LoginGuard:invalid-counter" }
                :if ($previous < 1) do={ :error "LoginGuard:nonpositive-counter" }
                :set failures ($previous + 1)
            }

            :if ($failures < $failureLimit) do={
                :if ([:len $counterEntry] = 0) do={
                    /ip firewall address-list add list=LoginGuardCount address=$srcText timeout=$failureWindow comment="1"
                } else={
                    /ip firewall address-list set $counterEntry comment=[:tostr $failures]
                }
                :return 0
            }

            /ip firewall address-list add list=BLOCK address=$srcText timeout=$banTime \
                comment=("LoginGuard:failures=" . $failures . ";service=" . $serviceName)
            :if ([:len $counterEntry] > 0) do={
                /ip firewall address-list remove $counterEntry
            }
            :log info ("LoginGuard:blocked src=" . $srcText . " service=" . $serviceName . " failures=" . $failures . " duration=" . $banTime)
        } do={
            :log error ("LoginGuard:handler-error error=" . $handlerError)
        }
    }

    /system logging action add name=LoginGuardAction target=script script=LoginGuard

    :local existingRules [/ip firewall filter find]
    /ip firewall filter add chain=input action=drop src-address-list=BLOCK disabled=yes \
        comment="LoginGuard:input-drop"
    :local guardRule [/ip firewall filter find where comment="LoginGuard:input-drop"]
    :if ([:len $existingRules] > 0) do={
        /ip firewall filter move $guardRule destination=[:pick $existingRules 0]
    }
    /ip firewall filter enable $guardRule

    /system logging add topics=system,critical regex="^login failure for user " action=LoginGuardAction \
        comment="LoginGuard:login-failure"
    :log info "LoginGuard:installed window=5m limit=4 ban=1d"
}

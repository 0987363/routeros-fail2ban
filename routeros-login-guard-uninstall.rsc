{
    /system logging remove [find where action="LoginGuardAction"]

    :if ([:len [/system script job find where script="LoginGuard"]] > 0) do={
        :error "LoginGuard:uninstall-busy-retry"
    }

    /system logging action remove [find where name="LoginGuardAction"]
    /system script remove [find where name="LoginGuard"]
    /ip firewall filter remove [find where comment="LoginGuard:input-drop" and chain=input and action=drop and src-address-list=BLOCK]
    /ip firewall address-list remove [find where list="LoginGuardCount"]
    /ip firewall address-list remove [find where list="BLOCK" and comment~"^LoginGuard:failures="]

    :log info "LoginGuard:uninstalled whitelist=preserved other-block-entries=preserved"
}

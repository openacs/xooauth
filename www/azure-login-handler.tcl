set login_url [ms::azure login_url]
set logout_url [ms::azure logout_url]

if {[ns_queryget id_token] ne ""} {
    set data [ms::azure perform_login]

    if {[dict exists $data user_id] && [dict get $data user_id] > 0} {
        #
        # Login was performed, we are done here.
        #
        ad_returnredirect [ms::azure cget -after_successful_login_url]
        ad_script_abort
    }
    #
    # This section is for debugging/development and failed requests.
    # Provide the returned data nicely formatted.
    #
    set cooked_claims [expr {[dict exists $data claims]
                             ? [string cat " " [join [lmap {k v} [dict get $data claims] { set _ "$k: $v" }] "\n "]]
                             : ""}]

    if {[dict exists $data claims]} {
        set claims [dict get $data claims]
    }
    set restdata $data
    dict unset restdata claims
    set cooked_data [join [lmap {k v} $restdata { set _ "$k: $v" }] "\n "]

    if {[dict exists $data error]} {
        #
        # Something went wrong, make sure to log out from Azure in all
        # error cases.
        #
        #ad_returnredirect -allow_complete_url [:logout_url]
        ns_http run [ms::azure logout_url]

        set error [dict get $data error]
    }

}

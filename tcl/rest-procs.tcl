::xo::library doc {
    Support for some REST APIs

    @author Gustaf Neumann
}

namespace eval ::xo {

    ###########################################################
    #
    # xo::REST class:
    #
    # Base class to support for some REST APIs
    #
    ###########################################################

    nx::Class create REST {

        #
        # The client_id/client_secret identifies the registered "app"
        # for which later app-tokens are used to issue action via the
        # REST interface.
        #
        :property {client_id}
        :property {client_secret}

        :method init {} {
            #
            # Make sure, we have the nsv array for application tokens
            # defined.
            #
            nsv_set -default app_token [self] ""

            #
            # Set defaults for instance variables from the
            # configuration file. This lookup is fairly generic and
            # takes into account the configure parameter of subclasses
            # of xo::REST. The parameters are looked up on a path
            # consisting of the namespace of the defining class and
            # the instance name. So, for the Microsoft Graph interface
            # defined as
            #
            #     ::ms::Graph create myapp
            #
            # the path is "ns/server/$server/ms/myapp". The lookup
            # will be performed at least for the "client_id" and
            # "client_secret".
            #
            set clientName [namespace tail [self]]
            set namespace [string trimleft [namespace parent [:info class]] :]
            set section "ns/server/[ns_info server]/$namespace/$clientName"
            set configureParameters [lmap p [:info lookup variables] {
                namespace tail $p
            }]
            ns_log notice "[self] configure parameters: $configureParameters"

            foreach param $configureParameters {
                ns_log notice "[self] config '$section' ns_param '$param'" \
                    "already set" [info exists :$param]

                if {![info exists :$param]} {
                    set value [ns_config $section $param]
                    if {$value ne ""} {
                        ns_log notice "config '$section' ns_param '$param' -> '$value'"
                        set :$param $value
                    }
                }
            }
            next
        }

        :method expect_status_code {r status_codes} {
            set status [dict get $r "status"]
            if {$status ni $status_codes} {
                set error ""
                if {[dict exists $r JSON]} {
                    set jsonDict [dict get $r JSON]
                    if {[dict exists $jsonDict error]} {
                        set error ([dict get $jsonDict error])
                    }
                }
                set context "[:uplevel {current methodpath}] [:uplevel {current args}]"
                set msg "[self] $context: expected status code $status_codes got $status $error"
                ns_log notice $msg "\n[ns_set array [dict get $r headers]]"
                error $msg
            }
            if {[dict exists $r JSON]} {
                return [dict get $r JSON]
            }
        }


        :method with_json_result {rvar} {
            :upvar $rvar r
            set content_type [ns_set iget [dict get $r headers] content-type ""]
            if {[string match "application/json*" $content_type]} {
                dict set r JSON  [:json_to_dict [dict get $r body]]
            }
            return $r
        }

        :public method pp {{-list:switch} {-prefix ""}  dict} {
            #
            # Simple pretty-print function which is based on the
            # conventions of the dict structures as returned from
            # Microsoft Graph API. Multi-valued results are returned in a dict
            # member named "value", which are printed indented and
            # space separated.
            #
            set r ""
            if {$list} {
                foreach e $dict {
                    append r [:pp -list=0 -prefix $prefix $e] \n
                }
                return $r
            }

            foreach {k v} $dict {
                if {$k eq "value"} {
                    append r $prefix $k ": " \n
                    foreach e $v {
                        append r [:pp -prefix "    $prefix" $e] \n
                    }
                } else {
                    append r $prefix $k ": " $v \n
                }
            }
            return $r
        }

        :method body {
            {-content_type "application/json; charset=utf-8"}
            {-vars ""}
        } {
            #
            # Build a body based on the provided variable names. The
            # values are retrieved via uplevel calls.
            #

            #
            # Get the caller of the caller (and ignore next calling levels).
            #
            set callinglevel [:uplevel [current callinglevel] [list current callinglevel]]
            #ns_log notice "CURRENT CALLING LEVEL $callinglevel " \
                [:uplevel $callinglevel [list info vars]] \
                [:uplevel $callinglevel [list info level 0]]

            #foreach level {2 3} {
            #    set cmd [lindex [:uplevel $level [list info level 0]] 0]
            #    ns_log notice "$cmd check for vars '$vars' on level $level, have: [:uplevel $level [list info vars]]"
            #    if {$cmd ne ":request"} break
            #}

            if {[string match "application/json*" $content_type]} {
                #
                # Convert var bindings to a JSON structure. This supports
                # an interface somewhat similar to export_vars but
                # supports currently as import just a list of variable
                # names with a suffix of either "array" (when value is a
                # list) or "triples" (for processing a triple list as
                # returned by e.g. mongo::json::parse).
                #
                return [:typed_list_to_json [concat {*}[lmap p $vars {
                    if {[regexp {^(.*):([a-z]+)(,[a-z]+)?$} $p . prefix suffix type]} {
                        set type [expr {$type eq "" ? "string" : [string range $type 1 end]}]
                        if {$suffix eq "array"} {
                            set values [:uplevel $callinglevel [list set $prefix]]
                            set result {}; set c 0
                            foreach v $values {
                                lappend result [list [incr c] $type $v]
                            }
                            list $prefix array [concat {*}$result]
                        } else {
                            list $prefix $suffix [:uplevel $callinglevel [list set $prefix]]
                        }
                    } else {
                        if {![:uplevel $callinglevel [list info exists $p]]} continue
                        list $p string [:uplevel $callinglevel [list set $p]]
                    }
                }]]]
            } else {
                return [:uplevel $callinglevel [list export_vars $vars]]
            }
        }

        :method request {
            {-method:required}
            {-content_type "application/json; charset=utf-8"}
            {-token}
            {-vars ""}
            {-url:required}
        } {
            set tokenArgs [expr { [info exists token]
                                  ? [list "Authorization" "Bearer $token"]
                                  : {} }]
            if {$vars ne "" || $method eq "POST"} {
                set body [:body -content_type $content_type -vars $vars]
                set r [ns_http run \
                           -method $method \
                           -headers [ns_set create headers {*}$tokenArgs "Content-type" $content_type] \
                           -expire 30 \
                           -body $body \
                           $url]
            } else {
                set r [ns_http run \
                           -method $method \
                           -headers [ns_set create headers {*}$tokenArgs] \
                           -expire 10 \
                           $url]
            }
            set content_type [ns_set iget [dict get $r headers] content-type ""]
            ns_log notice "[self] $method $url\n" \
                [expr {[info exists body] ? "$body\n" : ""}] \
                "Answer: $r ($content_type)"
            return [:with_json_result r]
        }

        :method json_to_dict {json_string} {
            #
            # Convert JSON to a Tcl dict and add it to the result
            # dict.
            #
            if {[info command ::json::json2dict] eq ""} {
                package require json
            }
            return [::json::json2dict $json_string]
        }

        :method typed_value_to_json {type value} {
            switch $type {
                "string" {
                    set escaped [string map [list \n \\n \t \\t \" \\\" \\ \\\\] $value]
                    return [subst {"$escaped"}]
                }
                "array" {
                    set r {}
                    foreach {pos t v} $value {
                        lappend r [:typed_value_to_json $t $v]
                    }
                    return "\[[join $r ,]\]"
                }
                "document" {
                    set r {}
                    foreach {name t v} $value {
                        lappend r [subst {"$name":[:typed_value_to_json $t $v]}]
                    }
                    return "{[join $r ,]}"
                }
            }
            return $value
        }

        :method typed_list_to_json {triples} {
            #
            # Convert a list of triples (name, type, value) into json/bson
            # notation. In case, there is mongodb support, use it,
            # otherwise use a simple approximation.
            #
            # The "type" element of the triple is used to determine value
            # formatting, such as e.g. quoting.
            #
            if {[info commands ::mongo::json::generate] ne ""} {
                ns_log notice "typed_list_to_json (mongo): $triples"
                return [::mongo::json::generate $triples]
            } else {
                ns_log notice "typed_list_to_json (tcl): $triples"
                set result ""
                foreach {name type value} $triples {
                    lappend result [subst {"$name":[:typed_value_to_json $type $value]}]
                }
                return "{[join $result ,]}"
            }
        }
        # ... :typed_list_to_json {
        #    mailnickname string gn
        #    active boolean true
        #    name string "Gustaf Neumann"
        #    x int 1
        # }

    }
}

::xo::library source_dependent
#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 2
#    indent-tabs-mode: nil
# End

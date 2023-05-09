::xo::library doc {
    Support for oauth authorization API

    @author Gustaf Neumann
}

::xo::library require rest-procs

#
# Namespace of oauth handlers
#
namespace eval ::xo::oauth {}

namespace eval ::xo {

    ###########################################################
    #
    # xo::Authorize class:
    #
    # Base class to support OAuth authorization API
    #
    ###########################################################

    nx::Class create ::xo::Authorize -superclasses ::xo::REST {
        :property {pretty_name}
        :property {base_url}
        :property {responder_url}

        :property {after_successful_login_url /pvt/}
        :property {login_failure_url /}

        :property {create_not_registered_users:switch false}
        :property {create_with_dotlrn_role ""}

        :property {scope}
        :property {debug:switch false}

        :public method login_url {
            {-state}
            {-login}
        } {
            #
            # Returns the URL for log-in
            #
            set base ${:base_url}/authorize
            set client_id ${:client_id}
            set scope ${:scope}
            set state [::xo::oauth::nonce]
            set redirect_uri "[ad_url]${:responder_url}"

            return [export_vars -no_empty -base $base {
                client_id redirect_uri state scope login
            }]
        }

        :method redeem_code {code} {
            set client_id ${:client_id}
            set client_secret ${:client_secret}
            set redirect_uri "[ad_url]${:responder_url}"
            set url [export_vars -no_empty -base ${:base_url}/access_token {
                client_id client_secret code redirect_uri
            }]
            set data [ns_http run $url]
            if {[dict get $data status] ne 200} {
                dict set data error oacs-cant_redeem_code
                dict set data error_description $data
            } else {
                set form_data [ns_set array [ns_parsequery [dict get $data body]]]
                ns_log notice "[self] redeem_code formdata has keys: [lsort [dict keys $form_data]]"
                if {![dict exists $form_data access_token]} {
                    if {[dict exists $form_data error]} {
                        dict set data error [dict get $form_data error]
                        dict set data error_description [dict get $form_data error_description]
                    } else {
                        dict set data error oacs-no_access_token
                        dict set data error_description $form_data
                    }
                } else {
                    dict set data access_token [dict get $form_data access_token]
                }
            }
            ns_log notice "[self] redeem_code returns $data"
            return $data
        }

        :public method logout {} {
            #
            # Perform logout operation from oauth in the background
            # (i.e. without a redirect) when the logout_url is
            # nonempty.
            #
            set url [:logout_url]
            if {$url ne ""} {
                ns_http run $url
            }
        }

        :public method name {} {
            return [expr {[info exists :pretty_name]
                          ? ${:pretty_name}
                          : [namespace tail [self]]}]
        }


        :method lookup_user_id {-email} -returns integer {
            set user_id [party::get_by_email -email [string tolower $email]]
            if {$user_id eq ""} {
                #
                # Here one could do some more checks or alternative lookups
                #
            }
            return [expr {$user_id eq "" ? 0 : $user_id}]
        }

        :method required_fields {} {
            return [expr {${:create_not_registered_users}
                          ? "email given_name family_name" 
                          : "email"}]
        }
        
        :method get_required_fields {
            {-claims:required}
            {-mapped_fields:required}           
        } {
            #
            # Check, if required fields are provided in the claims and
            # perform the name mapping between what was provided from
            # the identity provided and what we need in OpenACS.
            #
            set result ""

            set fields {}
            foreach pair $mapped_fields {
                lassign $pair field target
                dict set fields $target [dict get $claims $field]
            }
            dict set result fields $fields
            foreach field [:required_fields] {
                if {![dict exists $fields $field]
                    || [dict get $fields $field] in {"" "null"}
                } {
                    set not_enough_data $field
                    break
                }
            }
            
            if {[info exists not_enough_data]} {
                ns_log warning "[self] get_user_data: not enough data:" \
                    $not_enough_data "is missing"
                dict set result error oacs-not_enough_data
            }
            return $result
        }

        :method register_new_user {
            {-first_names}
            {-last_name}
            {-email}
        } -returns integer {
            #
            # Register the user and return the user_id. In case, the
            # registration of the new user fails, raise an exception.
            #
            # not tested
            #
            db_transaction {
                set user_info(first_names) $first_names
                set user_info(last_name) $last_name
                if {![util_email_unique_p $email]} {
                    error "Email is not unique: $email"
                }
                set user_info(email) $email
                array set creation_info [auth::create_local_account \
                                             -authority_id [auth::authority::local] \
                                             -username $email \
                                             -array user_info]
                if {$creation_info(creation_status) ne "ok"} {
                    error "Error when creating user: $creation_info(creation_status) $creation_info(element_messages)"
                }
                set user_id $creation_info(user_id)
                #
                # One might add here a callback to handle cases, where
                # externally provided identities should be added to a
                # database.
                #
                #db_dml _ "INSERT INTO azure_users VALUES (:user_id)"
                #db_dml _ "INSERT INTO azure_user_mails (user_id, email) VALUES (:user_id, :email)"

                if {[apm_package_installed_p dotlrn] && ${:create_with_dotlrn_role} ne ""} {
                    #
                    # We have DotLRN installed, and we want to create
                    # for this register object the new users in the
                    # provided role. Note that one can define
                    # different instances of this class behaving
                    # differently.
                    #
                    dotlrn::user_add \
                        -type ${:create_with_dotlrn_role} \
                        -can_browse=1 \
                        -id $email \
                        -user_id $user_id

                    acs_privacy::set_user_read_private_data \
                        -user_id $user_id \
                        -object_id [dotlrn::get_package_id] \
                        -value 1
                }
            } on_error {
                ns_log error "OAuth Login (Error during user creation): $errmsg ($email)"
                error "OAuth user creation failed: $errmsg"
            }
            return $user_id
        }

        :public method perform_login {-token} {
            #
            # Get the provided claims from the identity provider and
            # perform an OpenACS login, when the user exists.
            #
            # In case the user does not exist, create it optionally (when
            # "create_not_registered_users" is activated.
            #
            # When the user is created, and dotlrn is installed, the
            # new user might be added optionally as a dotlrn user with
            # the role as specified in "create_with_dotlrn_role".
            #
            set data [:get_user_data -token $token]
            if {[dict exists $data error]} {
                #
                # There was already an error in the steps leading to
                # this.
                #
                ns_log warning "[self] OAuth login failed:" \
                    [dict get $data error] "\n$data"

            } elseif {![dict exists $data email]} {
                #
                # No error and no email in result... actually, this
                # should not happen.
                #
                dict set data error oacs-no_email_in_result
                ns_log warning "OAuth login failed strangely: " \
                    [dict get $data error] "\n$data"

            } else {
                set user_id [:lookup_user_id -email [dict get $data email]]
                if {!${:debug}
                    && $user_id == 0
                    && ${:create_not_registered_users}
                } {
                    try {
                        :register_new_user \
                            -first_names [dict get $data given_name] \
                            -last_name [dict get $data family_name] \
                            -email [dict get $data email]
                    } on ok {result} {
                        set user_id $result
                    } on error {errorMsg} {
                        dict set data error oacs-register_failed
                        dict set data error_description $errorMsg
                    }
                }
                dict set data user_id $user_id
                if {$user_id != 0} {
                    #
                    # The lookup of the user_id was successful. We can
                    # login as this user.... but only, when no "debug"
                    # is activated.
                    #
                    if {!${:debug}} {
                        ad_user_login -external_registry [self] $user_id
                    }
                } else {
                    #
                    # For the time being, just report data back to the
                    # calling script.
                    #
                    dict set data error "oacs-no_such_user"
                }
            }
            return $data
        }
    }

    ####################################################################
    # Tailored OAuth handler for GitHub
    ####################################################################

    nx::Class create ::xo::oauth::GitHub -superclasses ::xo::Authorize {

        :property {pretty_name "GitHub"}
        :property {base_url https://github.com/login/oauth}
        :property {responder_url /oauth/github-login-handler}
        :property {scope {read:user user:email}}

        :method get_api_data {access_token} {
            set data [ns_http run \
                          -headers [ns_set create query Authorization "Bearer $access_token"] \
                          https://api.github.com/user]
            if {[dict get $data status] ne 200} {
                dict set result error oacs-cant_get_api_data
                dict set result error_description $data
            } else {
                set json_body [dict get $data body]
                dict set result claims [:json_to_dict $json_body]
            }
            ns_log notice "[self] get_api_data $access_token returns $result"
            return $result
        }

        :public method get_user_data {
            -token
            {-required_fields {
                {email email}
                {name name}
            }}
        } {
            #
            # Get user data based on the temporary code (passed via
            # "-token") provided by GitHub.  First, convert the
            # temporary code into an access_token, and use this to get
            # the user data.
            #
            set data [:redeem_code $token]
            ns_log notice "[self] redeem_code returned keys: [lsort [dict keys $data]]"
            set result $data

            if {[dict exists $data access_token]} {
                #
                # When we received the access_token, we have no error
                # so far.
                #
                set access_token [dict get $data access_token]
                #ns_log notice "[self] redeemed form data: $access_token"
                set result [:get_api_data $access_token]
                ns_log notice "[self] get_user_data: get_api_data contains error:" \
                    [dict exists $result error]

                if {![dict exists $result error]} {
                    set data [:get_required_fields \
                                  -claims [dict get $result claims] \
                                  -mapped_fields {
                                      {email email}
                                      {name name}
                                  }]
                    if {[dict exists $data error]} {
                        set result [dict merge $data $result]
                    } else {
                        set result [dict merge $result [dict get $data fields]]
                        #
                        # We have still to split up "name" into its
                        # components, since GitHub does not provide
                        # the exactly needed fields. Actually, we need
                        # this just for creating a new user_id, so it
                        # might not be always needed.
                        #
                        set first_names [join [lrange [dict get $result name] 0 end-1] " "]
                        set last_name [lindex [dict get $result name] end]
                        dict set result first_names $first_names
                        dict set result last_name $last_name
                    }
                }
            }
            ns_log notice "[self] get_user_data returns $result"
            return $result
        }

        :public method logout_url { {page ""} } {
            #
            # Returns the URL for logging out. E.g., GitHub has no
            # logout, so provide simply a redirect URL (maybe, we
            # should logout from the application?)
            #
            return $page
        }

    }

}
::xo::library source_dependent
#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 2
#    indent-tabs-mode: nil
# End

::xo::library doc {
    LTI procs - Basic interface classes for integrating LTI based tools

    @author Guenter Ernst
    @author Gustaf Neumann
    @author Michael Aram
}

namespace eval ::xo {

    ##################################################################################
    # Sample configuration for LTI plugins
    #
    # #
    # # Define/override LTI parameters in section $server/lti
    # #
    # ns_section ns/server/$server/lti {
    #     #
    #     # Common information for the tool consumer instance
    #     #
    #     ns_param tool_consumer_info_product_family_code "LEARN"
    #     ns_param tool_consumer_instance_guid  "learn.wu.ac.at"
    #     ns_param tool_consumer_instance_name  "WU Wien"
    # }
    #
    # ns_section ns/server/$server/lti/bbb {
    #     ns_param launch_url         "https://demo.bigbluebutton.org/lti/rooms/messages/blti"
    #     ns_param oauth_consumer_key "bbb"
    #     ns_param shared_secret      "..."
    # }
    #
    # ns_section ns/server/$server/lti/jupyter {
    #     ns_param launch_url         "https://..."
    #     ns_param shared_secret      "..."
    #     ns_param oauth_consumer_key "..."
    # }
    #
    # ns_section ns/server/$server/lti/zoom {
    #     ns_param launch_url         "https://applications.zoom.us/lti/rich"
    #     ns_param oauth_consumer_key "..."
    #     ns_param shared_secret      "..."
    # }
    ##################################################################################

    nx::Class create ::xo::lti::LTI {
        #
        # Common Parameter
        #
        :property {lti_message_type "basic-lti-launch-request"}
        :property {lti_version "LTI-1p0"}
        :property {roles}
        :property {launch_presentation_document_target window}  ;# window or iframe
        :property {launch_presentation_css_url}
        :property {launch_presentation_width}
        :property {launch_presentation_height}

        #
        # Basic LTI Launch Request
        #
        :property {launch_presentation_return_url}
        :property {launch_url}
        :property {resource_link_id}
        :property {resource_link_title}                 ;# Deprecated in LTI 2.0. Use custom_resource_link_title
        :property {context_id}
        :property {context_title}                       ;# Deprecated in LTI 2.0. Use custom_context_title
        :property {context_label}                       ;# Deprecated in LTI 2.0. Use custom_context_label
        :property {lis_person_name_given}               ;# Deprecated in LTI 2.0. Use custom_*
        :property {lis_person_name_family}              ;# Deprecated in LTI 2.0. Use custom_*
        :property {lis_person_name_full}                ;# Deprecated in LTI 2.0. Use custom_*
        :property {lis_person_contact_email_primary}    ;# Deprecated in LTI 2.0. Use custom_*

        :property {tool_consumer_instance_guid}         ;# e.g. learn.wu.ac.at
        :property {tool_consumer_info_product_family_code} ;# Deprecated in LTI 2.0.
        :property {tool_consumer_instance_name}         ;# Deprecated in LTI 2.0. Use custom_*
        :property {tool_consumer_instance_description}  ;# Deprecated in LTI 2.0. Use custom_*
        :property {tool_consumer_instance_url}          ;# Deprecated in LTI 2.0. Use custom_*
        :property {tool_consumer_instance_contact_email};# Deprecated in LTI 2.0. Use custom_*

        :property {lis_outcome_service_url}             ;# LTI 1.1; return URL for placing outcome
                                                        ;# Return single numeric value that scores
                                                        ;# the value of launch activity.
        :property {lis_result_sourcedid}                ;# LTI 1.1; encrypted ticket provided by the LMS to
                                                        ;# ensure that the outcome is properly labeled for
                                                        ;# the particular user, course, and link that are
                                                        ;# involved in this interaction

        #
        # OAuth parameters
        #
        :property {oauth_version "1.0"}
        :property {oauth_signature_method "HMAC-SHA1"}
        :property {oauth_timestamp}
        :property {oauth_nonce}
        :property {oauth_consumer_key}

        :property {shared_secret}


        :object property {lti_params {

            lti_message_type
            lti_version
            roles
            launch_presentation_document_target
            launch_presentation_css_url
            launch_presentation_width
            launch_presentation_height

            launch_presentation_return_url
            launch_url
            resource_link_id
            resource_link_title
            context_id
            context_title
            context_label

            oauth_version
            oauth_timestamp
            oauth_signature_method
            oauth_nonce
            oauth_consumer_key

            lis_person_sourcedid
            lis_person_contact_email_primary
            lis_person_name_given
            lis_person_name_family
            lis_person_name_full

            tool_consumer_instance_guid
            tool_consumer_info_product_family_code
            tool_consumer_instance_name
            tool_consumer_instance_description
            tool_consumer_instance_url
            tool_consumer_instance_contact_email
        }}

        :method get_params_from_section {{-extra shared_secret} section} {
            #
            # Try to get every parameter from the specified config section
            #
            foreach param [concat [::xo::lti::LTI cget -lti_params] $extra] {
                if {![info exists :$param]} {
                    set value [ns_config $section $param]
                    #ns_log notice "get_params_from_section '$section' param '$param' -> '$value'"
                    if {$value ne ""} {
                        ns_log notice "get param '$param' from section '$section' -> '$value'"
                        set :$param $value
                    }
                }
            }
        }

        :method get_context {} {
            if {![ns_conn isconnected]} {
                ns_log warning "LTI get_context requires an active connection"
                return
            }
            if {[info exists :context_id]
                && [info exists :context_title]
                && [info exists :context_label]
            } {
                #
                # Everything is already set
                #
                return
            }

            set community_id ""
            #
            # Try to get community_id and community_name from dotlrn community.
            #
            if {[llength [info commands dotlrn_community::get_community_id]] > 0} {
                set community_id [dotlrn_community::get_community_id]
                if {$community_id ne ""} {
                    set community_name [lang::util::localize [dotlrn_community::get_community_name $community_id]]
                }
            }
            #
            # If there is still no community_id (and community_name)
            # get it from the subsite.
            #
            if {$community_id eq ""} {
                set community_id [ad_conn subsite_id]
                set community_name [subsite::get_element \
                                        -subsite_id $community_id \
                                        -element instance_name]
            }
            if {$community_id ne "" && ![info exists :context_id]} {
                set :context_id $community_id
            }
            if {$community_name ne ""} {
                if {![info exists :context_title]} {
                    set :context_title $community_name
                }
                if {![info exists :context_label]} {
                    set :context_label $community_name
                }
            }
        }

        :method init {} {
            #
            # Parameter precedence:
            #    1) configure parameters when lti handler is created
            #    2) configure file section /lti/$provider
            #    3) from configure file section /lti
            #
            # Iterate over class hierarchy until xo::lti::LTI is
            # reached and set paramters.
            #
            foreach c [:info precedence] {
                if {$c eq [current class]} {
                    break
                }
                set key [string tolower [namespace tail $c]]
                :get_params_from_section "ns/server/[ns_info server]/lti/$key"

            }
            #
            # Try to fill the gaps with the global LTI settings.
            #
            :get_params_from_section "ns/server/[ns_info server]/lti"

            if {![info exists :roles]} {
                set :roles [expr {[permission::permission_p \
                                       -party_id [::xo::cc user_id] \
                                       -object_id [ad_conn package_id] \
                                       -privilege "admin"] ? "Administrator" : "Learner"}]
            }
            set :lis_person_sourcedid [acs_user::get -element username]
            set :lis_person_contact_email_primary [acs_user::get -element email]
            set :lis_person_name_given [acs_user::get -element first_names]
            set :lis_person_name_family [acs_user::get -element last_name]
            set :lis_person_name_full "[acs_user::get -element last_name] [acs_user::get -element first_names]"
        }

        :public method form_render {
            {-height 700}
            {-sandbox "allow-same-origin allow-scripts allow-forms allow-top-navigation allow-popups allow-popups-to-escape-sandbox allow-downloads"}
            {-style "min-width:100%;width:100%;min-height:100%;"}
            {-auto_launch_p 0}
        } {
            #
            # Set per-call parameters
            #
            if {![info exists :oauth_timestamp]} {
                set :oauth_timestamp [::xo::oauth::timestamp]
            }
            if {![info exists :oauth_nonce]} {
                set :oauth_nonce [::xo::oauth::nonce]
            }
            :get_context

            #
            # Collect the provided parameters
            #
            set params {}
            set signature_parameters {}
            foreach param [::xo::lti::LTI cget -lti_params] {
                if {[info exists :$param]} {
                    lappend params $param
                    lappend signature_parameters [list $param [set :$param]]
                }
            }

            #
            # Add potential GET parameters from the launch_url to
            # the signature parameters.
            #
            set url_info [ns_parseurl ${:launch_url}]
            if {[dict exists $url_info query]} {
                foreach {key value} [ns_set array [ns_parsequery [dict get $url_info query]]] {
                    lappend signature_parameters [list $key $value]
                }
            }

            security::csp::require form-action ${:launch_url}
            security::csp::require frame-src ${:launch_url}

            #
            # Create signature
            #
            set signature [[::xo::oauth::Signature new \
                                -volatile \
                                -base_string_uri [::xo::oauth::Signature base_string_from_url ${:launch_url}] \
                                -signature_parameters $signature_parameters \
                                -client_secret ${:shared_secret}] generate]

            set lti_form_parameters $signature_parameters
            lappend lti_form_parameters [list oauth_signature $signature]
            #ns_log notice "==================== lti_form_parameters = $lti_form_parameters"

            #
            # We need an autogenerated frame name, because otherwise,
            # cascaded LTI frames may have the same name, which causes
            # trouble. However, we might need a configuration option
            # to allow opening up in _parent frames.
            #
            if { ${:launch_presentation_document_target} eq "iframe"} {
                set iframe_name "ltiframe${:oauth_nonce}"
                set target "ltiframe${:oauth_nonce}"
            } else {
                set iframe_name ""
                set target "_blank"
            }

            set form_name ltiform_${:oauth_nonce}
            set wrapper_id ltiLaunchFormSubmitArea_${:oauth_nonce}

            #
            # Create the HTML form.
            #
            ::xo::require_html_procs
            dom createDocument div lti
            $lti appendFromScript {
                ::html::div id $wrapper_id  {
                    ::html::form \
                        target $target \
                        action ${:launch_url} \
                        name $form_name id $form_name method "POST" \
                        encType "application/x-www-form-urlencoded" {
                            foreach pair $lti_form_parameters {
                                lassign $pair k v
                                ::html::input type hidden name $k value $v
                            }
                        }
                }
                #
                # Add iframe if needed
                #
                if {${:launch_presentation_document_target} eq "iframe"} {
                    ::html::iframe name $target \
                        style $style \
                        height $height \
                        sandbox $sandbox
                }

            }

            # auto launch
            if {$auto_launch_p} {
                template::add_body_handler \
                    -event onload \
                    -script [subst -nocommands {document.getElementById('$form_name').submit();}]
            }

            set html [$lti asHTML]
            $lti delete

            if {${:launch_presentation_document_target} eq "window"} {
                ::template::add_footer -html $html
                set html ""
            }

            return [list HTML $html form_name $form_name iframe_name $iframe_name]
        }
    }

    nx::Class create ::xo::lti::BBB -superclass ::xo::lti::LTI {
        :property {launch_presentation_document_target window}  ;# window or iframe
    }

    nx::Class create ::xo::lti::Jupyter -superclass ::xo::lti::LTI {
        :property {launch_presentation_document_target window}  ;# window or iframe
    }

    nx::Class create ::xo::lti::Zoom -superclass ::xo::lti::LTI {
        :property {launch_presentation_document_target iframe}  ;# window or iframe
    }
}

#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 2
#    indent-tabs-mode: nil
# End

::xo::library doc {
    LTI includelet procs for xowiki - Providing LTI launch buttons as includelets

    @author Guenter Ernst
    @author Gustaf Neumann
    @author Michael Aram
}

::xo::library require -package xowiki includelet-procs

namespace eval ::xowiki::includelet {

    ###############################################################################
    # Includelet for an LTI launchbutton for BigBlueButton
    ################################################################################

    ::xowiki::IncludeletClass create LTI-LaunchButton \
        -superclass ::xowiki::Includelet \
        -parameter {
            {title ""}
            {__decoration none}
            {launch_button_label "Join Meeting"}
            {launch_button_title "Click to join"}
            {title ""}
            {presentation "window"}
            {parameter_declaration {
                {-launch_button_label "Join Meeting"}
                {-launch_button_title "Click to join"}
                {-title ""}
                {-presentation "window"}
            }}
        }
    LTI-LaunchButton instproc init args {
        #
        # Map parameters of class to the configurable includelet
        # parameters to ease syntax of LTI button definitions
        #
        set result {}
        foreach pair ${:parameter_declaration} {
            lassign $pair k v
            if {$k eq "-launch_button_label"} {
                set v ${:launch_button_label}
            } elseif {$k eq "-launch_button_title"} {
                set v ${:launch_button_title}
            } elseif {$k eq "-title"} {
                set v ${:title}
            } elseif {$k eq "-presentation"} {
                set v ${:presentation}
            }
            lappend result [list $k $v]
        }
        set :parameter_declaration $result
        next
    }

    LTI-LaunchButton instproc render_form_button {
        -class
        -resource_link_id
        -resource_link_title
        -launch_button_title
        -launch_button_label
        -return_url
    } {
        set lti [$class new \
                     -resource_link_id $resource_link_id \
                     -resource_link_title $resource_link_title \
                     -launch_presentation_return_url $return_url \
                    ]
        set result [$lti form_render]
        $lti destroy

        return [subst {
            <adp:button class="btn btn-primary" title="$launch_button_title"
            type="submit" form="[dict get $result form_name]">$launch_button_label</adp:button>
            [dict get $result HTML]
        }]
    }



    ###############################################################################
    # Includelet for an LTI launchbutton for BigBlueButton
    ################################################################################
    ::xowiki::IncludeletClass create launch-bigbluebutton \
        -superclass LTI-LaunchButton \
        -parameter {
        }

    launch-bigbluebutton instproc render {} {
        :get_parameters
        return [:render_form_button \
                    -class ::xo::lti::BBB  \
                    -resource_link_id [${:__including_page} item_id] \
                    -resource_link_title $title \
                    -launch_button_title $launch_button_title \
                    -launch_button_label $launch_button_label \
                    -return_url [ad_return_url -qualified]]
    }

    ###############################################################################
    # Includelet for an LTI launchbutton for Jupyter
    ################################################################################
    ::xowiki::IncludeletClass create launch-jupyter \
        -superclass LTI-LaunchButton \
        -parameter {
            {launch_button_label "Start Jupyter"}
            {launch_button_title "Click to start"}
        }

    launch-jupyter instproc render {} {
        :get_parameters
        return [:render_form_button \
                    -class ::xo::lti::Jupyter  \
                    -resource_link_id [${:__including_page} item_id] \
                    -resource_link_title $title \
                    -launch_button_title $launch_button_title \
                    -launch_button_label $launch_button_label \
                    -return_url [ad_return_url -qualified]]
    }

    ###############################################################################
    # Includelet for an LTI launchbutton for Zoom
    ################################################################################
    ::xowiki::IncludeletClass create launch-zoom \
        -superclass  LTI-LaunchButton \
        -parameter {
        }

    launch-zoom instproc render {} {
        :get_parameters
        set return_url [ad_return_url -qualified]
        if {$presentation ne "window"} {
            append return_url /web-conference-2-ended
        }
        return [:render_form_button \
                    -class ::xo::lti::Zoom  \
                    -resource_link_id [${:__including_page} item_id] \
                    -resource_link_title $title \
                    -launch_button_title $launch_button_title \
                    -launch_button_label $launch_button_label \
                    -return_url $return_url]
    }

}

::xo::library source_dependent

#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 2
#    indent-tabs-mode: nil
# End

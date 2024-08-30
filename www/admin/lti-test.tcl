ad_page_contract {
    LTI Testpage for LIT (e.g. including Zoom)

    @author Guenter Ernst
}

auth::require_login

set chunk ""

ad_form \
    -name zoom\
    -form {
        {launch_url:text(url)
            {label {Launch URL}}
            {value "https://lti.tools/saltire/tp"}
        }
        {oauth_consumer_key:text(text)
            {label {Consumer Key}}
            {value "mychoice"}
        }
        {secret:text(text)
            {label {Secret}}
            {value "secret"}
        }
        {username:text(text),optional
            {label {Username}}
        }
        {roles:text(text)
            {label {Role}}
            {value "Learner"}
        }
        {presentation:oneof(select)
            {label "Presentation"}
            {options { {Window window} {IFrame iframe}}}
            {values "iframe"}
        }
        {p:text(textarea),optional
            {label {Additional Parameters}}
            {html {rows 10 cols 80}}
            {help_text {Add additional parameters to the launch request.
                        Provide key-value pairs in the form key=value
                        with one pair per line. The default values are
                        just an example.}}
            {value {context_id=cid-00113
context_label=SI106
context_title=Design of Personal Environments 1
launch_presentation_locale=en_us
lis_person_contact_email_primary=me.myself@myhome.org
lis_person_name_family=Myself
lis_person_name_given=Me
resource_link_description=My Test Page
resource_link_id=12345_test_page
resource_link_title=My LTI Test Page
user_id=me100}}
        }
        {autosubmit_p:boolean(radio)
            {label {Autologin}}
            {options {{On true} {Off false}}}
            {help_text {Toggle autologin. If "Off" is selected a "Launch"-button
                        will be displayed beneath this form.}}
            {value false}
        }
    } -on_submit {

        # additional parameter
        set lti_parameter ""
        if {$p ne ""} {
           foreach pair [split $p "\n"] {
               if {[regexp {^([^=]+)=([^=]+)$} $pair . key value]} {
                   lappend lti_params $key $value
               }
           }
        }

         # param username
        if {$username eq ""} {
            set username [acs_user::get_element \
                        -user_id [ad_conn user_id] \
                        -element "username" \
                      ]
        }


        set params(user_id) "$username"

        # presentation
        if {$presentation ni {window iframe}} {
            set presentation "iframe"
        }
        set params(launch_presentation_document_target) $presentation


        #  submit button
        set basiclti_submit "Launch"
        set params(basiclti_submit) $basiclti_submit

        #
        # iframe
        #
        # Note: we do not set any kind of sandboxing here, but it
        # could be appropriate. See
        # https://developer.mozilla.org/en-US/docs/Web/HTML/Element/iframe#sandbox
        #
        set iframe_attributes {
            style "min-width:100%;border:0px;min-height:800px;resize:both;overflow:auto;"
        }

        # default parameter
        set params(lti_version) "LTI-1p0"
        set params(lti_message_type) "basic-lti-launch-request"
        set params(oauth_version) "1.0"

        set params(oauth_signature_method) "HMAC-SHA1"
        set params(oauth_nonce) [::xo::oauth::nonce]
        set params(oauth_timestamp) [::xo::oauth::timestamp]
        set launch_url ${launch_url}

        set params(oauth_consumer_key) $oauth_consumer_key
        set shared_secret $secret

        set params(role) $roles

        # add additional LTI parameter
        if {[info exists lti_params] && $lti_params ne ""} {
            foreach {key value} $lti_params {
                set params($key) $value
            }
        }

        # ------------------------------------------------------------------------------
        # LTI Request and form creation
        # ------------------------------------------------------------------------------
        foreach k [array names params] {
            lappend signature_parameters [list $k $params($k)]
        }

        set lti_form_parameters $signature_parameters

        ## Add potential GET parameters from the launch url to the signature parameters
        array set uri [uri::split $launch_url]
        foreach {key value} [ns_set array [ns_parsequery $uri(query)]] {
           lappend signature_parameters [list $key $value]
        }

        # signature
        set signature [[::xo::oauth::Signature new \
                            -volatile \
                            -base_string_uri [::xo::oauth::Signature base_string_from_url $launch_url] \
                            -signature_parameters $signature_parameters \
                            -client_secret $shared_secret] generate]

        lappend lti_form_parameters [list oauth_signature $signature]

        # We need an autogenerated frame name, because otherwise, cascaded lti frames
        # may have the same name, which causes trouble. However, we might need a configuration
        # option to allow opening up in _parent frames
        set target [expr { $params(launch_presentation_document_target) eq "iframe" ? "ltiframe$params(oauth_nonce)" : "_blank" }]
        set form_name ltiform
        set wrapper_id ltiLaunchFormSubmitArea

        # create the form
        xo::require_html_procs
        dom createDocument div lti
        $lti appendFromScript {
            ::html::div id $wrapper_id  {
                ::html::form \
                    target $target \
                    action $launch_url \
                    name $form_name id $form_name method "POST" \
                    encType "application/x-www-form-urlencoded" {
                        foreach pair $lti_form_parameters {
                            lassign $pair k v
                                if {$k eq "basiclti_submit"} {
                                    ::html::input type submit name basiclti_submit value $basiclti_submit {}
                                } else {
                                    ::html::input type hidden name $k value $v
                                }
                        }
                    }
            }

            if {$params(launch_presentation_document_target) eq "iframe"} {
                ::html::iframe name $target {*}$iframe_attributes
            }

            if {$autosubmit_p} {
                # AUTO-SUBMIT
                ::html::script {
                    ::html::t [subst -nocommands {
                                document.getElementById('$wrapper_id').style.display = 'none';
                                nei = document.createElement('input');
                                nei.setAttribute('type', 'hidden');
                                nei.setAttribute('name', 'basiclti_submit');
                                nei.setAttribute('value', '$basiclti_submit');
                                document.getElementById('$form_name').appendChild(nei);
                                document.$form_name.submit();
                                } ]
                }
            }
        }

        set chunk [$lti asHTML]
        $lti delete

    }

ad_return_template

#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 4
#    indent-tabs-mode: nil
# End:

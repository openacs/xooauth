# TODO: Handle cases, where we have no callback URL provided, as
# described in: http://tools.ietf.org/html/rfc5849#section-2.2
set client_title [$client title]
set client_description [$client description]
set oauth_verifier [$temp_credentials verifier]
set temp_credentials_id [$temp_credentials temp_credentials_id]
set oauth_token [$temp_credentials identifier]
set oauth_callback [$temp_credentials callback]
set redirect_url [export_vars -base $oauth_callback {oauth_token oauth_verifier}]

$temp_credentials msg $redirect_url
ad_form -name authorize_temp_token -export {oauth_token redirect_url} -form {
  temp_credentials_id:key
} -edit_request {
} -on_submit {
  # TODO: Here, we should either delete the token or invalidate it?
} -after_submit {
  ad_returnredirect -allow_complete_url $redirect_url
  ad_script_abort
}

#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 2
#    indent-tabs-mode: nil
# End:

::xo::library doc {
    Support for the Canvas REST API

    The Canvas REST API provides proper encodings for query and POST
    parameters (requests can be submitted as url-encoded or as JSON)
    and translates the reply into Tcl dicts. The API support also
    Canvas Pagination (https://canvas.instructure.com/doc/api/file.pagination.html)

    To call the Canvas REST API, one has to create an "app", which must
    acquire an access token from the Microsoft identity platform. The
    access token contains information about your app and the permissions
    it has for the resources and APIs available through Microsoft
    Graph. To get an access token, your app must be registered with the
    Microsoft identity platform and be authorized by either a user or an
    administrator for access to the Microsoft Graph resources it needs.

    https://docs.microsoft.com/en-us/graph/auth/auth-concepts
    https://docs.microsoft.com/en-us/graph/auth-register-app-v2

    In theory, this API will allow later to switch to newer versions of
    the Graph API when newer versions (currently post 1.0) of the
    Microsoft Graph API will come out.


    @author Gustaf Neumann
}

::xo::library require rest-procs

namespace eval ::canvas {

    ##################################################################################
    # Sample configuration for Canvas Graph API
    #
    # #
    # # Define/override Canvas setup parameters in section $server/canvas
    # #
    # ns_section ns/server/$server/canvas
    #
    # ns_section ns/server/$server/canvas/app {
    #     #
    #     # Defaults for client ID and secret for the app
    #     # (administrative agent) "canvas::app", which might
    #     # be created via
    #     #
    #     #    ::canvas::API create ::canvas::app
    #     #
    #     # The parameters can be as well provided in the
    #     # create command above.
    #     #
    #     ns_param client_id     "..."
    #     ns_param client_secret "..."
    #     ns_param baseurl       "https://your.org/"
    #     ns_param version       "v1"
    # }
    #

    ###########################################################
    #
    # canvas::API class:
    #
    # Support for the CANVAS REST API
    # https://canvas.instructure.com/doc/api/
    #
    ###########################################################

    nx::Class create API -superclasses ::xo::REST {
        #
        # Basic Canvas API for OAuth calls. For details, see
        # https://canvas.instructure.com/doc/api/
        #
        # @param baseurl starting URL
        # @param token   auth token
        # @param version Version of the API
        #
        
        :property {baseurl}
        :property {token}
        :property {version v1}

        :method request {
            {-method:required}
            {-content_type "application/json; charset=utf-8"}
            {-token}
            {-vars ""}
            {-url:required}
        } {
            if {[string match http* $url]} {
                #
                # If we have a full URL, just pass everything up
                #
                set result [next]
            } else {
                #
                # We have a relative URL (has to start with a
                # slash). Prepend "https://graph.microsoft.com" as
                # prefix.
                #
                set tokenArg [expr {[info exists token] ? [list -token $token] : {}}]
                set result [next [list \
                                      -method $method \
                                      -content_type $content_type \
                                      {*}$tokenArg \
                                      -vars $vars \
                                      -url ${:baseurl}/api/${:version}$url]]
            }
            #ns_log notice HEADERS=[:pp [ns_set array [dict get $result headers]]]
            #
            # handle Canvas pagination (return current/next/first link)
            #
            foreach entry [:parse_link_value [ns_set iget [dict get $result headers] link ""]] {
                ns_log notice "CHECK '$entry'"
                if {[dict exists $entry params] && [dict exists $entry url]} {
                    foreach param [dict get $entry params] {
                        if {[lindex $param 0] eq "rel"} {
                            dict set result link [lindex $param 1] [dict get $entry url]
                        }
                    }
                }
            }
            return $result
        }

        :public method token {
            {-grant_type "client_credentials"}
            {-scope ""}
            {-assertion ""}
            {-client_assertion_type "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"}
            -requested_token_use
        } {
            #
            # Get bearer token (access token) from the /oauth2/v2.0/token endpoint.
            #
            # https://canvas.instructure.com/doc/api/file.oauth_endpoints.html#post-login-oauth2-token
            #

            #error "not implemented yet"

            #
            # Get the access-token from /token endpoint.
            #
            set r [:request -method POST \
                       -content_type "application/x-www-form-urlencoded" \
                       -vars {
                           {client_secret ${:client_secret}}
                           {client_id ${:client_id}}
                           scope
                           grant_type
                           assertion
                           client_assertion_type
                           requested_token_use
                       } \
                       -url ${:baseurl}/login/oauth2/token]

            ns_log notice "/token POST Request Answer: $r"
            #
            # Current errors:
            #   assertion method not supported for this grant_type"
            #   <h1>Page Error</h1> <p>Something broke unexpectedly.
            #
            #return $access_token
        }

        :method parse_link_params {pairs} {
            lmap pair $pairs {
                set pair [string trim $pair]
                if {![regexp {^(.*)=(.*)$} $pair . key value]} continue
                list $key [string trim $value \"]
            }
        }

        :method parse_link_value {link} {
            #
            # Parse the provided link.
            #
            
            # Link           = "Link" ":" #("<" URI ">" *( ";" link-param )
            # link-param     = ( ( "rel" "=" relationship )
            #                 | ( "rev" "=" relationship )
            #                 | ( "title" "=" quoted-string )
            #                 | ( "anchor" "=" <"> URI <"> )
            #                 | ( link-extension ) )
            # link-extension = token [ "=" ( token | quoted-string ) ]
            set result ""
            while {1} {
                if {$link eq ""} {
                    break
                }
                set startURL [string first < $link]
                set endURL [string first > $link]
                if {$startURL == -1 || $endURL == -1 || $startURL > $endURL} {
                    error "invalid link header field: '$link'"
                }
                set url [string range $link $startURL+1 $endURL-1]
                set remainder [string range $link $endURL+1 end]
                if {[regexp {^\s*[;]\s*(.*)$} $remainder . remainder]} {
                    # has params
                    set endParams [string first , $remainder]
                    if {$endParams == -1} {
                        set params $remainder
                        set remainder ""
                    } else {
                        set params [string range $remainder 0 $endParams-1]
                        set remainder [string range $remainder $endParams+1 end]
                    }
                    set params [:parse_link_params [split $params ";"]]
                    lappend result [list url $url params $params]
                }
                set link $remainder
            }
            return $result
        }

        :method params {varlist} {
            #
            # parameter encoding following the parameter conventions
            # in Canvas
            #
            set params {}
            foreach var $varlist {
                if {[regexp {^(.*):array$} $var . var]} {
                    set values [:uplevel [list set $var]]
                    if {$values eq ""} continue
                    foreach value $values {
                        lappend params $var\[\]=[ad_urlencode_query $value]
                    }
                } else {
                    set value [:uplevel [list set $var]]
                    if {$value eq ""} continue
                    lappend params $var=[ad_urlencode_query $value]
                }
            }
            return [join $params &]
        }

        :method paginated_result_list {-max_entries r expected_status_code} {
            #
            # By default, Canvas returns for a query just the first 10
            # results ("pagination"). To obtain more results, it is
            # necessary to issue multiple requests. If "max_entries" is
            # specified, the interface tries to get the requested
            # number of entries. If there are less entries available,
            # just these are returned.
            #
            set resultList [:expect_status_code $r $expected_status_code]
            if {$max_entries ne ""} {
                while {1} {
                    set got [llength $resultList]
                    ns_log notice "[self] paginated_result_list: got $got max_entries $max_entries"
                    if {$got >= $max_entries} {
                        set resultList [lrange $resultList 0 $max_entries-1]
                        break
                    }
                    if {[dict exists $r link] && [dict exists [dict get $r link] next]} {
                        set r [:request -method GET -token ${:token} \
                                   -url [dict get [dict get $r link] next]]
                        lappend resultList {*}[:expect_status_code $r 200]
                    } else {
                        #ns_log notice "=== No next link"
                        break
                    }
                }
            }
            return $resultList
        }

        ###########################################################
        # canvas::API "account" ensemble
        ###########################################################

        :public method "account admins" {
            account_id:integer
            {-page 1}
            {-per_page 10}
            {-max_entries ""}
        } {
            #
            # Get a paginated list of the admins in the account.
            #
            # Details: https://canvas.instructure.com/doc/api/admins.html
            #
            # @param page Return the nth page of the result set
            # @param per_page Return this number of entries per page
            # @param max_entries perform potentially multiple requests
            # until the requested number of entries can be returned.
            #
            set r [:request -method GET -token ${:token} \
                       -url /accounts/${account_id}/admins]
            return [:paginated_result_list -max_entries $max_entries $r 200]
        }

        :public method "account courses" {
            account_id:integer
            {-with_enrollments ""}
            {-enrollment_type ""}
            {-published ""}
            {-completed ""}
            {-blueprint ""}
            {-blueprint_associated ""}
            {-by_teachers ""}
            {-by_subaccounts ""}
            {-hide_enrollmentless_courses ""}
            {-state ""}
            {-enrollment_term_id ""}
            {-search_term ""}
            {-include ""}
            {-sort ""}
            {-order ""}
            {-search_by ""}
            {-starts_before ""}
            {-ends_after ""}
            {-homeroom ""}
            {-page 1}
            {-per_page 10}
            {-max_entries ""}
        } {
            #
            # Retrieve a paginated list of courses in this account.
            #
            # Details: https://canvas.instructure.com/doc/api/accounts.html
            #
            # @param with_enrollments If true, include only courses
            # with at least one enrollment. If false, include only
            # courses with no enrollments. If not present, do not
            # filter on course enrollment status.
            #
            # @param enrollment_type If set, only return courses that
            # have at least one user enrolled in the course with
            # one of the specified enrollment types. Allowed values:
            # teacher, student, ta, observer, designer
            #
            # @param published If true, include only published
            # courses. If false, exclude published courses. If not
            # present, do not filter on published status.
            #
            # @param completed If true, include only completed courses
            # (these may be in state 'completed', or their enrollment
            # term may have ended). If false, exclude completed
            # courses. If not present, do not filter on completed
            # status.
            #
            # @param blueprint If true, include only blueprint
            # courses. If false, exclude them. If not present, do not
            # filter on this basis.
            #
            # @param blueprint_associated If true, include only
            # courses that inherit content from a blueprint course. If
            # false, exclude them. If not present, do not filter on
            # this basis.
            #
            # @param by_teachers List of User IDs of teachers; if
            # supplied, include only courses taught by one of the
            # referenced users.
            #
            # @param by_subaccounts List of Account IDs; if supplied,
            # include only courses associated with one of the
            # referenced subaccounts.
            #
            # @param hide_enrollmentless_courses If present, only
            # return courses that have at least one
            # enrollment. Equivalent to 'with_enrollments=true';
            # retained for compatibility.
            #
            # @param state If set, only return courses that are in the
            # given state(s). By default, all states but “deleted” are
            # returned. Allowed values: created, claimed, available,
            # completed, deleted, all.
            #
            # @param enrollment_term_id If set, only includes courses
            # from the specified term.
            #
            # @param search_term If set, only includes courses
            # from the specified term.
            #
            # @param include List of extra values to be included.
            # Allowed values: syllabus_body, term, course_progress,
            # storage_quota_used_mb, total_students, teachers,
            # account_name, concluded
            #
            # @param sort The column to sort results by. Allowed
            # values: course_name, sis_course_id, teacher,
            # account_name
            #
            # @param order the order to sort the given column
            # by. Allowed values: asc, desc
            #
            # @param search_by The filter to search by. “course”
            # searches for course names, course codes, and SIS
            # IDs. “teacher” searches for teacher names Allowed
            # values: course, teacher
            #
            # @param starts_before If set, only return courses that
            # start before the value (inclusive) or their enrollment
            # term starts before the value (inclusive) or both the
            # course's start_at and the enrollment term's start_at are
            # set to null. The value should be formatted as:
            # yyyy-mm-dd or ISO 8601 YYYY-MM-DDTHH:MM:SSZ.
            #
            # @param ends_after If set, only return courses that end
            # after the value (inclusive) or their enrollment term
            # ends after the value (inclusive) or both the course's
            # end_at and the enrollment term's end_at are set to
            # null. The value should be formatted as: yyyy-mm-dd or
            # ISO 8601 YYYY-MM-DDTHH:MM:SSZ.
            #
            # @param homeroom If set, only return homeroom courses.
            #
            # @param page Return the nth page of the result set
            # @param per_page Return this number of entries per page
            # @param max_entries perform potentially multiple requests
            # until the requested number of entries can be returned.
            #
            set r [:request -method GET -token ${:token} \
                       -url /accounts/${account_id}/courses?[:params {page per_page
                           with_enrollments enrollment_type:array
                           published completed blueprint blueprint_associated
                           by_teachers:array by_subaccounts:array
                           hide_enrollmentless_courses state:array
                           enrollment_term_id search_term
                           include:array sort order search_by
                           starts_before ends_after homeroom
                           }]]
            return [:paginated_result_list -max_entries $max_entries $r 200]
        }

        :public method "account get" {
            account_id:integer
        } {
            #
            # Retrieve information on an individual account, given by
            # id or sis sis_account_id.
            #
            # Details: https://canvas.instructure.com/doc/api/accounts.html

            set r [:request -method GET -token ${:token} \
                       -url /accounts/${account_id}]
            return [:expect_status_code $r 200]
        }

        :public method "account list" {
            {-page 1}
            {-per_page 10}
            {-max_entries ""}
        } {
            #
            # A paginated list of accounts that the current user can
            # view or manage. Typically, students and even teachers
            # will get an empty list in response, only account admins
            # can view the accounts that they are in.
            #
            # Details: https://canvas.instructure.com/doc/api/accounts.html
            #
            # @param page Return the nth page of the result set
            # @param per_page Return this number of entries per page
            # @param max_entries perform potentially multiple requests
            # until the requested number of entries can be returned.
            #
            set r [:request -method GET -token ${:token} \
                       -url /accounts?[:params {page per_page}]]
            return [:paginated_result_list -max_entries $max_entries $r 200]
        }


        :public method "account permissions" {
            account_id:integer
            {-permissions ""}
        } {
            #
            # Returns permission information for the calling user and
            # the given account. You may use `self` as the account id
            # to check permissions against the domain root
            # account. The caller must have an account role or admin
            # (teacher/TA/designer) enrollment in a course in the
            # account.
            #
            # Details: https://canvas.instructure.com/doc/api/accounts.html
            set r [:request -method GET -token ${:token} \
                       -url /accounts/${account_id}/permissions?[:params {permissions:array}]]
            return [:expect_status_code $r 200]
        }

        :public method "account settings" {
            account_id:integer
        } {
            #
            # Returns all of the settings for the specified account as
            # a JSON object. The caller must be an Account admin with
            # the manage_account_settings permission.
            #
            # Details: https://canvas.instructure.com/doc/api/accounts.html

            set r [:request -method GET -token ${:token} \
                       -url /accounts/${account_id}/settings]
            return [:expect_status_code $r 200]
        }

        ###########################################################
        # canvas::API "course" ensemble
        ###########################################################

        :public method "course users" {
            course_id:integer
            {-search_term ""}
            {-sort ""}
            {-enrollment_type ""}
            {-enrollment_role_id ""}
            {-include ""}
            {-user_ids ""}
            {-enrollment_state ""}
            {-page 1}
            {-per_page 10}
            {-max_entries ""}
        } {
            #
            # Returns the paginated list of users in this course. And
            # optionally the user's enrollments in the course.
            #
            # Details: https://canvas.instructure.com/doc/api/courses.html
            #
            # @param search_term The partial name or full ID of the
            # users to match and return in the results list.
            #
            # @param sort When set, sort the results of the search
            # based on the given Allowed values: username, last_login,
            # email, sis_id
            #
            # @param enrollment_type When set, only return users where
            # the user is enrolled as this type. “student_view”
            # implies include[]=test_student. This argument is ignored
            # if enrollment_role is given. Allowed values: teacher,
            # student, student_view, ta, observer, designer
            #
            # @param enrollment_role_id When set, only return courses
            # where the user is enrolled with the specified
            # course-level role. This can be a role created with the
            # Add Role API or a built_in role id with type
            # 'StudentEnrollment', 'TeacherEnrollment',
            # 'TaEnrollment', 'ObserverEnrollment', or
            # 'DesignerEnrollment'.
            #
            # @param include Optionally included content.  Allowed
            # values: enrollments, locked, avatar_url, test_student,
            # bio, custom_links, current_grading_period_scores, uuid
            #
            # @param include Optionally included content.  Allowed
            # values: enrollments, locked, avatar_url, test_student,
            # bio, custom_links, current_grading_period_scores, uuid
            #
            # @param user_ids If included, the course users set will
            # only include users with IDs specified by the
            # param.
            #
            # @param enrollment_state When set, only return users
            # where the enrollment workflow state is of one of the
            # given types. “active” and “invited” enrollments are
            # returned by default.  Allowed values: active, invited,
            # rejected, completed, inactive
            #
            # @param page Return the nth page of the result set
            # @param per_page Return this number of entries per page
            # @param max_entries perform potentially multiple requests
            # until the requested number of entries can be returned.
            #
            set r [:request -method GET -token ${:token} \
                       -url /courses/${course_id}/users?[:params {page per_page
                           search_term sort enrollment_type:array enrollment_role_id
                           include:array user_ids:array enrollment_state:array
                       }]]
            return [:paginated_result_list -max_entries $max_entries $r 200]
        }

        :public method "course activities" {
            course_id:integer
            {-page 1}
            {-per_page 10}
            {-max_entries ""}
        } {
            #
            # Returns the paginated Returns the current user's
            # course-specific activity stream, paginated.
            #
            # Details: https://canvas.instructure.com/doc/api/courses.html
            #
            # @param page Return the nth page of the result set
            # @param per_page Return this number of entries per page
            # @param max_entries perform potentially multiple requests
            # until the requested number of entries can be returned.
            #
            set r [:request -method GET -token ${:token} \
                       -url /courses/${course_id}/activity_stream?[:params {page per_page}]]
            return [:paginated_result_list -max_entries $max_entries $r 200]
        }

        :public method "course todo" {
            course_id:integer
            {-page 1}
            {-per_page 10}
            {-max_entries ""}
        } {
            #
            # Returns a paginated list of the current user's
            # course-specific todo items.
            #
            # Details: https://canvas.instructure.com/doc/api/courses.html
            #
            # @param page Return the nth page of the result set
            # @param per_page Return this number of entries per page
            # @param max_entries perform potentially multiple requests
            # until the requested number of entries can be returned.
            #
            set r [:request -method GET -token ${:token} \
                       -url /courses/${course_id}/todo?[:params {page per_page}]]
            return [:paginated_result_list -max_entries $max_entries $r 200]
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

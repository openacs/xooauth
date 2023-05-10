::xo::library doc {
    Support for the Microsoft Graph API

    These interface classes support conversion from/to JSON and to the
    urlencoded calling patterns on the fly, just by specifying the Tcl
    variable names mith minor annotations (somewhat similar to the
    export_vars interface). Furthermore, the interface supports
    pagination: some Microsoft Graph API calls return per default just
    a partial number of results (e.g. first 100). To obtain all
    results multiple REST calls have to be issued to get the full
    result set. Over this interface, one can specify the desired
    maximum number of entries.

    To use the Microsoft Graph API, an "app" has to be
    registered/configured/authorized/...[1,2,3] by an administrator of
    the organization before an access token [4] can be obtained token from
    the Microsoft identity platform. The access token contains
    information about your app and the permissions it has for the
    resources and APIs available through Microsoft Graph.

    This Interface is based on access tokens [4] and the /token endpoint
    [1] ("Get access without a user") and assumes, one has already
    obtained the client_id and client_secret to configure this service
    this way.

    In theory, this API will allow later to switch to newer versions of
    the Graph API when newer versions (currently post 1.0) of the
    Microsoft Graph API will come out.

    @author Gustaf Neumann

    [1] https://docs.microsoft.com/en-us/graph/auth-v2-service
    [2] https://docs.microsoft.com/en-us/graph/auth/auth-concepts
    [3] https://docs.microsoft.com/en-us/graph/auth-register-app-v2
    [4] https://oauth.net/id-tokens-vs-access-tokens/
}
::xo::library require rest-procs

namespace eval ::ms {

    ##################################################################################
    # Sample configuration for Microsoft Graph API
    #
    # #
    # # Define/override MS parameters in section $server/ms
    # #
    #
    # ns_section ns/server/$server/ms {
    #     ns_param client_id     "..."
    # }
    #
    # #
    # # and/or in the section named after the interface object.
    # #
    #
    # ns_section ns/server/$server/ms/app {
    #     #
    #     # Defaults for client ID and secret for the app
    #     # (administrative agent) "ms::app", which might
    #     # be created via
    #     #
    #     #    ::ms::Graph create ::ms::app
    #     #
    #     # The parameters can be as well provided in the
    #     # create command above.
    #     #
    #     ns_param client_id     "..."
    #     ns_param client_secret "..."
    #     ns_param tenant        "..."
    #     ns_param version       "v1.0"
    # }
    #

    ###########################################################
    #
    # ms::Graph class:
    #
    # Support for the Microsoft Graph API
    # https://docs.microsoft.com/en-us/graph/use-the-api
    #
    ###########################################################

    nx::Class create Graph -superclasses ::xo::REST {
        #
        # The "tenant" identifies an organization within azure.  One
        # OpenACS installation might talk to different tenants at the
        # same time, in which case multiple instances of the Ms
        # Class (or one of its subclasses) must be created.
        #
        # Possible values for the "tenant" property:
        #  - "common": Allows users with both personal Microsoft accounts
        #    and work/school accounts from Azure AD to sign into the
        #    application.
        #
        #  - "organizations": Allows only users with work/school accounts
        #    from Azure AD to sign into the application.
        #
        #  - "consumers": Allows only users with personal Microsoft
        #    accounts (MSA) to sign into the application.
        #
        #  - tenant GUID identifier, or friendly domain name of the Azure
        #    AD, such as e.g. xxxx.onmicrosoft.com
        #
        # Details: https://docs.microsoft.com/en-us/azure/active-directory/develop/active-directory-v2-protocols
        #

        :property {tenant}

        :property {version v1.0}    ;# currently just used in URL generation

        :public object method run_donecallback {
            serialized_app_obj
            location
            callback
        } {
            #
            # Helper method for running callbacks. In general, we
            # cannot rely that the interface object (typically
            # ms::app) exists also in the job-queue, where atjobs are
            # executed. Therefore, the class method receives everything
            # to reconstruct the used interface object.
            #

            set name [eval $serialized_app_obj]
            #ns_log notice "serialized_app_obj $serialized_app_obj ===> $name"
            $name run_donecallback $location $callback
        }


        :public method token {
            {-grant_type "client_credentials"}
            {-scope "https://graph.microsoft.com/.default"}
            -assertion
            -requested_token_use
        } {
            #
            # Get bearer token (access token) from the /oauth2/v2.0/token endpoint,
            # with timestamp validation (based on "expires_in") result.
            #
            # Obtaining the access token is MsGraph
            # dependent. Probably, some of this can be factored out
            # later to one of the super classes.
            #
            # @param scope with prefconfigured permissions: use "https://graph.microsoft.com/.default"
            #
            # Comment: This method performs its own caching via nsvs. It
            # would be better to use the ns_cache framework with it's
            # built-in expiration methods via ns_cache_eval, but we get
            # the expiration time provided from the non-cached call and
            # not upfront, before this call. We do not want to use a hack
            # with double ns_cache calls, so we leave this for the time
            # being.
            #
            if {[nsv_get app_token [self] tokenDict] && $tokenDict ne ""} {
                set access_token [dict get $tokenDict access_token]
                set expiration_date [dict get $tokenDict expiration_date]
                #
                # If access token exists and is not expired we simply
                # return it here
                #
                if {$access_token != "" && $expiration_date > [clock seconds]} {
                    #ns_log notice "---- using token and expiration_date from nsv: " \
                                                                                    #    "$access_token / $expiration_date (vs. now: [clock seconds])"
                    return $access_token
                }
            }

            #
            # Get the access-token from /token endpoint.
            # Details: https://docs.microsoft.com/en-us/graph/auth-v2-service
            #
            set r [:request -method POST \
                       -content_type "application/x-www-form-urlencoded" \
                       -vars {
                           {client_secret ${:client_secret}}
                           {client_id ${:client_id}}
                           scope
                           grant_type
                           assertion
                           requested_token_use
                       } \
                       -url https://login.microsoftonline.com/${:tenant}/oauth2/v2.0/token]

            ns_log notice "/token POST Request Answer: $r"
            if {[dict get $r status] != "200"} {
                error "[self] authentication request returned status code [dict get $r status]"
            }

            set jsonDict [dict get $r JSON]
            if {![dict exists $jsonDict access_token]} {
                error "[self] authentication must return access_token. Got: [dict keys $jsonDict]"
            }

            if {[dict exists $jsonDict expires_in]} {
                set expire_secs [dict get $jsonDict expires_in]
            } else {
                #
                # No "expires_in" specified, fall back to some default.
                #
                set expire_secs 99999
            }

            #
            # Save access-token and expiration date for this request
            #
            set access_token [dict get $jsonDict access_token]
            set expiration_date [clock add [clock seconds] $expire_secs seconds]
            nsv_set app_token [self] [list \
                                          access_token $access_token \
                                          expiration_date $expiration_date]
            return $access_token
        }


        #
        # Parameter encoding conventions for MSGraph
        #
        :method encode_query {param value} {
            return \$$param=[ad_urlencode_query $value]
        }
        :method params {varlist} {
            #
            # Support for OData query parameters: Encode vars as query
            # variables in case these are not empty.
            #
            join [lmap var $varlist {
                set value [:uplevel [list set $var]]
                if {$value eq ""} continue
                :encode_query $var $value
            }] &
        }

        :method paginated_result_list {-max_entries r expected_status_code} {
            #
            # By default, MSGraph returns for a query just the first 100
            # results ("pagination"). To obtain more results, it is
            # necessary to issue multiple requests. If "max_entries" is
            # specified, the interface tries to get the requested
            # number of entries. If there are less entries available,
            # just these are returned.
            #
            set resultDict [:expect_status_code $r $expected_status_code]
            set resultList {}

            if {$max_entries ne ""} {
                while {1} {
                    #
                    # Handle pagination in Microsoft Graph. Since the
                    # list is returned in the JSON element "value", we
                    # have to extract these values and update it later
                    # with the result of potentially multiple
                    # requests.
                    # Details: https://docs.microsoft.com/en-us/graph/paging
                    #
                    set partialResultList ""
                    set nextLink ""
                    if {[dict exists $r JSON]} {
                        set JSON [dict get $r JSON]
                        if {[dict exists $JSON value]} {
                            set partialResultList [dict get $JSON value]
                        }
                        if {[dict exists $JSON @odata.nextLink]} {
                            set nextLink [dict get $JSON @odata.nextLink]
                        }
                    }

                    lappend resultList {*}$partialResultList

                    set got [llength $resultList]
                    ns_log notice "[self] paginated_result_list: got $got max_entries $max_entries"
                    if {$got >= $max_entries} {
                        set resultList [lrange $resultList 0 $max_entries-1]
                        break
                    }
                    if {$nextLink ne ""} {
                        set r [:request -method GET -token [:token] -url $nextLink]
                        set resultDict [:expect_status_code $r 200]
                    } else {
                        #ns_log notice "=== No next link"
                        break
                    }
                }
                dict set resultDict value $resultList
            }
            return $resultDict
        }

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
                next
            } else {
                #
                # We have a relative URL (has to start with a
                # slash). Prepend "https://graph.microsoft.com" as
                # prefix.
                #
                set tokenArg [expr {[info exists token] ? [list -token $token] : {}}]
                next [list \
                          -method $method \
                          -content_type $content_type \
                          {*}$tokenArg \
                          -vars $vars \
                          -url https://graph.microsoft.com/${:version}$url]
            }
        }

        :method check_async_operation {location} {
            #
            # For async operations, the MSGraph API returns the
            # location to be checked for finishing via the "location"
            # reply header field. Perform the checking only when the
            # location has the expected structure.
            #
            #ns_log notice "check_async_operation $location"

            if {![regexp {^/teams\('([^']+)'\)/operations\('([^']+)'\)$} $location . id opId]} {
                error "teams check_async_operation '$location' is not in the form of /teams({id})/operations({opId})"
            }

            set r [:request -method GET -token [:token] -url ${location}]

            #ns_log notice "/checkAsync GET Answer: $r"
            set status [dict get $r status]
            if {$status == 200} {
                set jsonDict [dict get $r JSON]
                ns_log notice "check_async_operation $location -> [dict get $jsonDict status]"
                return [dict get $jsonDict status]
            } elseif {$status == 404} {
                #
                # MSGraph returns sometimes 404 even for valid
                # operation IDs. Probably, the call was to early for
                # the cloud....
                #
                return NotFound
            }
            return $r
        }

        :public method schedule_donecallback {secs location callback} {
            #
            # Add an atjob for the for the done callback. The job is
            # persisted, such that even for long running operations
            # and server restarts, the operation will continue after
            # the server restart.
            #

            #ns_log notice "--- schedule_donecallback $secs $location $callback"
            set j [::xowf::atjob new \
                       -url [xo::cc url] \
                       -party_id [xo::cc user_id] \
                       -cmd $callback \
                       -time [clock format [expr {[clock seconds] + $secs}]]]
            $j persist
        }

        :public method run_donecallback {location callback} {
            #
            # Method to be finally executes the donecallback. First,
            # we have to check whether the async operation has already
            # finished. If this operation is still in progress,
            # reschedule this operation.
            #

            #ns_log notice "RUNNING donecallback <$callback>"
            set operationStatus [:check_async_operation $location]
            if {$operationStatus eq "inProgress"} {
                :schedule_donecallback 60 $location $callback
            } else {
                {*}$callback [expr {$operationStatus eq "succeeded"}] $operationStatus
            }
        }

        :method async_operation_status {{-wait:switch} {-donecallback ""} r} {
            #set context "[:uplevel {current methodpath}] [:uplevel {current args}]"
            :uplevel [list :expect_status_code $r 202]
            set location [ns_set iget [dict get $r headers] location]
            set operationStatus [:check_async_operation $location]
            ns_log notice "[self] async operation '$location' -> $operationStatus"
            #
            # Since this is an async operation, it might take a while,
            # until "the cloud" has finished. When the flag "-wait"
            # was specified, we try up to 10 more times with a backoff
            # time strategy. Microsoft recommends to wait >30 seconds
            # between checks, but actually, this seems overly
            # conservative for most application scenarios.
            #
            # TODO: If still everything fail until then, we
            # we should do a scheduled checking with a finish callback.
            #
            if {$wait && $operationStatus ne "succeeded"} {
                foreach \
                    i        {1  2  3  4   5   6   7   8   9  10} \
                    interval {1s 1s 3s 5s 10s 30s 30s 30s 30s 30s} \
                    {
                        ns_sleep $interval
                        set operationStatus [:check_async_operation $location]
                        ns_log notice "[self] retry $i: operationStatus $operationStatus"
                        if {$operationStatus eq "succeeded"} {
                            break
                        }
                    }
            }
            if {$donecallback ne ""} {
                #
                # Since we call the callback and its environment via
                # "eval", we have to protect the arguments with "list".
                #
                :schedule_donecallback 60 $location \
                    [list eval [current class] run_donecallback \
                         [list [:serialize]] [list $location] [list $donecallback]]
            }
            return $operationStatus
        }

        ###########################################################
        # ms::Graph "group" ensemble
        ###########################################################

        :public method "group get" {
            group_id
            {-select ""}
        } {
            #
            # Get the properties and relationships of a group object.
            # To get properties that are not returned by default,
            # specify them in a -select OData query option.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/group-get
            #
            # @param select return selected attributes, e.g. displayName,mail,visibility

            set r [:request -method GET -token [:token] \
                       -url /groups/$group_id?[:params {select}]]
            return [:expect_status_code $r 200]
        }

        :public method "group list" {
            {-count ""}
            {-expand ""}
            {-filter ""}
            {-orderby ""}
            {-search ""}
            {-select id,displayName,userPrincipalName}
            {-max_entries ""}
            {-top:integer,0..1 ""}
        } {
            #
            # To get a list of all groups in the organization that
            # have teams, filter by the resourceProvisioningOptions
            # property that contains "Team" (needs beta API):
            #    resourceProvisioningOptions/Any(x:x eq 'Team')
            # Otherwise, one has to get the full list and filter manually.
            #
            # Since groups are large objects, use $select to only get
            # the properties of the group you care about.
            #
            # Details:
            #    https://docs.microsoft.com/graph/teams-list-all-teams
            #    https://docs.microsoft.com/en-us/graph/query-parameters#filter-parameter
            #
            # @param count boolean, retrieves the total count of matching resources
            # @param expand retrieve related information via navigation property, e.g. members
            # @param filter retrieve a filtered subset of the tuples
            # @param orderby order tuples by some attribute
            # @param search returns results based on search criteria.
            # @param select return selected attributes, e.g. id,displayName,userPrincipalName
            # @param max_entries retrieve this desired number of tuples (potentially multiple API calls)
            # @param top return up this number of tuples per request (page size)

            # set filter "startsWith(displayName,'Information Systems') and resourceProvisioningOptions/Any(x:x eq 'Team')"
            # "contains()" seems not supported
            # set filter "contains(displayName,'Information Systems')"
            # set select {$select=id,displayName,resourceProvisioningOptions}

            set r [:request -method GET -token [:token] \
                       -url https://graph.microsoft.com/beta/groups?[:params {
                           count expand select filter orderby search top}]]
            return [:paginated_result_list -max_entries $max_entries $r 200]
        }

        :public method "group deleted" {
            {-count ""}
            {-expand ""}
            {-filter ""}
            {-orderby ""}
            {-search ""}
            {-select id,displayName,deletedDateTime}
            {-top:integer,0..1 ""}
        } {
            #
            # List deleted groups.
            #
            # Since groups are large objects, use $select to only get
            # the properties of the group you care about.
            #
            # Details: https://docs.microsoft.com/graph/api/directory-deleteditems-list
            #
            # @param expand retrieve related information via navigation property, e.g. members
            # @param count boolean, retrieves the total count of matching resources
            # @param filter retrieve a filtered subset of the tuples
            # @param orderby order tuples by some attribute
            # @param search returns results based on search criteria.
            # @param select return selected attributes, e.g. id,displayName,userPrincipalName
            # @param top sets the page size of results

            # set filter "startsWith(displayName,'Information Systems') and resourceProvisioningOptions/Any(x:x eq 'Team')"
            set r [:request -method GET -token [:token] \
                       -url /directory/deletedItems/microsoft.graph.group?[:params {
                           count expand filter orderby search select top}]]
            return [:expect_status_code $r 200]
        }

        #----------------------------------------------------------
        # ms::Graph "group member" ensemble
        #----------------------------------------------------------

        :public method "group member add" {
            group_id
            principals:1..n
        } {
            #
            # Add a conversationMember to a group.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/group-post-members
            #

            if {[llength $principals] > 20} {
                error "max 20 users can be added in one call"
            }
            set members@odata.bind [lmap id $principals {
                set _ "https://graph.microsoft.com/v1.0/directoryObjects/${id}"
            }]
            set r [:request -method PATCH -token [:token] \
                       -vars {members@odata.bind:array} \
                       -url /groups/${group_id}]
            return [:expect_status_code $r 204]
        }

        :public method "group memberof" {
            group_id
            {-count ""}
            {-filter ""}
            {-orderby ""}
            {-search ""}
        } {
            #
            # Get groups that the group is a direct member of.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/group-list-memberof
            #
            # @param count when "true" return just a count
            # @param filter  filter citerion
            # @param search search criterion, e.g. displayName:Video
            # @param orderby sorting criterion, e.g. displayName
            #
            set r [:request -method GET -token [:token] \
                       -url /groups/${group_id}/memberOf?[:params {
                           count filter orderby search}]]
            return [:expect_status_code $r 200]
        }

        :public method "group member list" {
            group_id
            {-count ""}
            {-filter ""}
            {-search ""}
            {-max_entries ""}
            {-top:integer,0..1 ""}

        } {
            #
            # Get a list of the group's direct members. A group can
            # have users, organizational contacts, devices, service
            # principals and other groups as members. Currently
            # service principals are not listed as group members due
            # to staged roll-out of service principals on Graph V1.0
            # endpoint.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/group-list-members
            #
            # @param count boolean, retrieves the total count of matching resources
            # @param filter retrieve a filtered subset of the tuples
            # @param search returns results based on search criteria.
            # @param top sets the page size of results
            # @param max_entries retrieve this desired number of tuples (potentially multiple API calls)

            set r [:request -method GET -token [:token] \
                       -url /groups/${group_id}/members?[:params {count filter search top}]]
            return [:paginated_result_list -max_entries $max_entries $r 200]
        }

        :public method "group member remove" {
            group_id
            principal
        } {
            #
            # Remove group member
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/group-delete-members
            #
            set r [:request -method DELETE -token [:token] \
                       -url /groups/${group_id}/members/${principal}/\$ref]
            return [:expect_status_code $r 204]
        }

        #----------------------------------------------------------
        # ms::Graph "group owner" ensemble
        #----------------------------------------------------------

        :public method "group owner add" {
            group_id
            principal
        } {
            #
            # add an owner to a group.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/group-post-owners
            #
            set @odata.id "https://graph.microsoft.com/v1.0/users/${principal}"
            set r [:request -method POST -token [:token] \
                       -vars {@odata.id} \
                       -url /groups/${group_id}/owners/\$ref]
            return [:expect_status_code $r 204]
        }

        :public method "group owner list" {
            group_id
        } {
            #
            # Retrieve a list of the group's owners.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/group-list-owners
            #
            set r [:request -method GET -token [:token] \
                       -url /groups/${group_id}/owners]
            return [:expect_status_code $r 200]
        }

        :public method "group owner remove" {
            group_id
            user_id
        } {
            #
            # Remove group owner
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/group-delete-owners
            #
            set r [:request -method DELETE -token [:token] \
                       -url /groups/${group_id}/owners/${user_id}/\$ref]
            return [:expect_status_code $r 204]
        }

        ###########################################################
        # ms::Graph "team" ensemble
        ###########################################################

        :public method "team archive" {
            team_id
            {-shouldSetSpoSiteReadOnlyForMembers ""}
            {-donecallback ""}
            {-wait:switch false}
        } {
            # Archive the specified team. When a team is archived,
            # users can no longer send or like messages on any channel
            # in the team, edit the team's name, description, or other
            # settings, or in general make most changes to the
            # team. Membership changes to the team continue to be
            # allowed.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/team-archive
            #
            # @param shouldSetSpoSiteReadOnlyForMembers This optional
            # parameter defines whether to set permissions for team
            # members to read-only on the SharePoint Online site
            # associated with the team. Setting it to false or
            # omitting the body altogether will result in this step
            # being skipped.
            #
            # @param wait when specified, perform up to 10 requests checking the status of the async command
            # @param donecallback cmd to be executed when the async
            #        command succeeded or failed. One additional argument is
            #        passed to the callback indicating the result status.
            #

            set r [:request -method POST -token [:token] \
                       -url /teams/$team_id/archive?[:params {shouldSetSpoSiteReadOnlyForMembers}]]
            return [:async_operation_status -wait=$wait -donecallback $donecallback $r]
        }

        :public method "team create" {
            -description
            -displayName:required
            -visibility
            -owner:required
            {-donecallback ""}
            {-wait:switch false}
        } {
            #
            # Create a new team.  A team owner must be provided when
            # creating a team in an application context.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/team-post
            #
            # @param wait when specified, perform up to 10 requests checking the status of the async command
            # @param donecallback cmd to be executed when the async
            #        command succeeded or failed. One additional argument is
            #        passed to the callback indicating the result status.
            #

            set template@odata.bind "https://graph.microsoft.com/v1.0/teamsTemplates('standard')"
            set members [subst {{
                @odata.type string "#microsoft.graph.aadUserConversationMember"
                roles array {0 string owner}
                user@odata.bind string "https://graph.microsoft.com/v1.0/users('$owner')"
            }}]
            set r [:request -method POST -token [:token] \
                       -vars {template@odata.bind description displayName visibility members:array,document} \
                       -url /teams]
            return [:async_operation_status -wait=$wait -donecallback $donecallback $r]
        }

        :public method "team clone" {
            team_id
            -classification
            -description
            -displayName:required
            -mailNickname:required
            -partsToClone:required
            -visibility
            {-donecallback ""}
            {-wait:switch false}
        } {
            #
            # Create a copy of a team specified by "team_id". It is
            # possible to copy just some parts of the old team (such
            # as "apps", "channels", "members", "settings", or "tabs",
            # or a comma-separated combination).
            #
            # @param team_id of the team to be cloned (might be a template)
            # @param partsToClone specify e.g. as "apps,tabs,settings,channels"
            # @param wait when specified, perform up to 10 requests checking the status of the async command
            # @param donecallback cmd to be executed when the async
            #        command succeeded or failed. One additional argument is
            #        passed to the callback indicating the result status.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/team-clone

            set r [:request -method POST -token [:token] \
                       -vars {
                           classification
                           description
                           displayName
                           mailNickname
                           partsToClone
                           visibility
                       } \
                       -url /teams/${team_id}/clone]
            return [:async_operation_status -wait=$wait -donecallback $donecallback $r]
        }

        :public method "team delete" {
            team_id
        } {
            # Delete group/team. When deleted, Microsoft 365 groups are
            # moved to a temporary container and can be restored
            # within 30 days. After that time, they're permanently
            # deleted.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/group-delete

            set r [:request -method DELETE -token [:token] \
                       -url /groups/$team_id]
            return [:expect_status_code $r 204]
        }

        :public method "team get" {
            team_id
            {-expand ""}
            {-select ""}
        } {
            #
            # Retrieve the properties and relationships of the
            # specified team.
            #
            # Every team is associated with a group. The group has the
            # same ID as the team - for example, /groups/{id}/team is
            # the same as /teams/{id}. For more information about
            # working with groups and members in teams,
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/team-get
            #
            # @param expand retrieve related information via navigation property, e.g. members
            # @param select select subset of attributes

            set r [:request -method GET -token [:token] \
                       -url /teams/$team_id?[:params {expand select}]]
            return [:expect_status_code $r 200]
        }

        :public method "team unarchive" {
            team_id
            {-donecallback ""}
            {-wait:switch false}
        } {
            # Restore an archived team. This restores users' ability to
            # send messages and edit the team, abiding by tenant and
            # team settings. Teams are archived using the archive API.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/team-unarchive
            #
            # @param wait when specified, perform up to 10 requests checking the status of the async command
            # @param donecallback cmd to be executed when the async
            #        command succeeded or failed. One additional argument is
            #        passed to the callback indicating the result status.

            set r [:request -method POST -token [:token] \
                       -url /teams/$team_id/unarchive]
            return [:async_operation_status -wait=$wait -donecallback $donecallback $r]
        }

        #----------------------------------------------------------
        # ms::Graph "team member" ensemble
        #----------------------------------------------------------

        :public method "team member add" {
            team_id
            principal
            {-roles member}
        } {
            #
            # Add a conversationMember to the collection of a team.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/team-post-members
            #
            set @odata.type "#microsoft.graph.aadUserConversationMember"
            set roles $roles
            set user@odata.bind "https://graph.microsoft.com/v1.0/users('${principal}')"

            set r [:request -method POST -token [:token] \
                       -vars {@odata.type roles:array user@odata.bind} \
                       -url https://graph.microsoft.com/${:version}/teams/${team_id}/members]
            return [:expect_status_code $r 201]
        }

        :public method "team member list" {
            team_id
            {-filter ""}
            {-select ""}
        } {
            #
            # Get the conversationMember collection of a team.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/team-list-members
            #
            # @param select select subset of attributes
            # @param filter restrict answers to a subset of tuples, e.g.
            #        (microsoft.graph.aadUserConversationMember/displayName eq 'Harry Johnson')

            set r [:request -method GET -token [:token] \
                       -url /teams/${team_id}/members?[:params {filter select}]]
            return [:expect_status_code $r 200]
        }

        :public method "team member remove" {
            team_id
            principal
        } {
            #
            # Remove a conversationMember from a team.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/group-delete-members

            set r [:request -method DELETE -token [:token] \
                       -url /teams/${team_id}/members/${principal}]
            return [:expect_status_code $r 204]
        }

        :public method "team channel list" {
            team_id
            {-filter ""}
            {-select ""}
            {-expand ""}
        } {
            #
            # Retrieve the list of channels in this team.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/channel-list
            #
            # @param filter retrieve a filtered subset of the tuples, e.g. "membershipType eq 'private'"
            # @param expand retrieve related information via navigation property, e.g. members
            # @param select select subset of attributes

            set r [:request -method GET -token [:token] \
                       -url /teams/${team_id}/channels?[:params {filter select expand}]]
            return [:expect_status_code $r 200]
        }


        ###########################################################
        # ms::Graph "application" ensemble
        ###########################################################
        :public method "application get" {
            application_id
            {-select ""}
        } {
            #
            # Get the properties and relationships of an application object.
            #
            # Details: https://docs.microsoft.com/graph/api/application-list
            #
            # @param select return selected attributes, e.g. id,appId,keyCredentials

            set r [:request -method GET -token [:token] \
                       -url /applications/${application_id}?[:params {select}]]
            return [:expect_status_code $r 200]
        }

        :public method "application list" {
            {-count ""}
            {-expand ""}
            {-filter ""}
            {-orderby ""}
            {-search ""}
            {-select ""}
            {-top:integer,0..1 ""}
        } {
            #
            # Get the list of applications in this organization.
            #
            # Details: https://docs.microsoft.com/graph/api/application-list
            #
            # @param expand retrieve related information via navigation property, e.g. members
            # @param count boolean, retrieves the total count of matching resources
            # @param filter retrieve a filtered subset of the tuples
            # @param orderby order tuples by some attribute
            # @param search returns results based on search criteria.
            # @param select return selected attributes, e.g. id,appId,keyCredentials
            # @param top sets the page size of results

            set r [:request -method GET -token [:token] \
                       -url /applications?[:params {
                           count expand filter orderby search select top}]]
            return [:expect_status_code $r 200]
        }

        ###########################################################
        # ms::Graph "chat" ensemble
        ###########################################################

        :public method "chat get" {
            chat_id
        } {
            #
            # Retrieve the properties and relationships of user object.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/chat-get
            #
            set r [:request -method GET -token [:token] \
                       -url /chats/$chat_id]
            return [:expect_status_code $r 200]
        }

        :public method "chat messages" {
            chat_id
            {-top:integer,0..1 ""}
        } {
            #
            # Retrieve the properties and relationships of user object.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/chat-list-messages
            #
            # @param top sets the page size of results (for chat, max is 50)

            set r [:request -method GET -token [:token] \
                       -url /chats/$chat_id/messages?[:params {top}]]
            return [:expect_status_code $r 200]
        }

        ###########################################################
        # ms::Graph "user" ensemble
        ###########################################################

        :public method "user get" {
            principal
            {-select ""}
        } {
            #
            # Retrieve the properties and relationships of user object.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/user-get
            #
            # @param select return selected attributes, e.g. displayName,givenName,postalCode

            set r [:request -method GET -token [:token] \
                       -url /users/$principal?[:params {select}]]
            return [:expect_status_code $r 200]
        }

        :public method "user list" {
            {-select "displayName,userPrincipalName,id"}
            {-filter ""}
            {-max_entries ""}
            {-top:integer,0..1 ""}
        } {
            #
            # Retrieve the properties and relationships of user
            # object.  For the users collection the default page size
            # is 100, the max page size is 999, if you try $top=1000
            # you'll get an error for invalid page size.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/user-list
            #
            # @param select return selected attributes, e.g. displayName,givenName,postalCode
            # @param filter restrict answers to a subset, e.g. "startsWith(displayName,'Neumann')"
            # @param max_entries retrieve this desired number of tuples (potentially multiple API calls)
            # @param top return up this number of tuples per request (page size)

            set r [:request -method GET -token [:token] \
                       -url /users?[:params {select filter top}]]
            return [:paginated_result_list -max_entries $max_entries $r 200]
        }

        :public method "user me" {
            {-select ""}
            {-token ""}
        } {
            #
            # Retrieve the properties and relationships of the current
            # user identified by the token.
            #
            # The "me" request is only valid with delegated authentication flow.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/user-get
            #
            # @param select return selected attributes, e.g. displayName,givenName,postalCode
            #
            if {$token eq ""} {
                set token [:token]
            }
            set r [:request -method GET -token $token \
                       -url /me?[:params {select}]]
            return [:expect_status_code $r 200]
        }

        :public method "user memberof" {
            principal
            {-count ""}
            {-filter ""}
            {-orderby ""}
            {-search ""}
        } {
            #
            # Get groups, directory roles, and administrative units that
            # the user is a direct member of.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/user-list-memberof
            #
            # @param count when "true" return just a count
            # @param filter  filter citerion
            # @param search search criterion, e.g. displayName:Video
            # @param orderby sorting criterion, e.g. displayName

            set r [:request -method GET -token [:token] \
                       -url /users/${principal}/memberOf?[:params {
                           count filter orderby search}]]
            return [:expect_status_code $r 200]
        }

    }


    ###########################################################
    #
    # ms::Authorize class:
    #
    # Support for the Microsoft Microsoft identity platform ID
    # tokens to login/logout via MS Azure accounts.
    # https://learn.microsoft.com/en-us/azure/active-directory/develop/id-tokens
    ###########################################################

    nx::Class create ::ms::Authorize -superclasses ::xo::Authorize {
        :property {pretty_name "Azure"}
        :property {tenant}
        :property {version ""}

        :property {responder_url /oauth/azure-login-handler}
        :property {scope {openid offline_access profile}}
        :property {response_type {code id_token}}

        :public method login_url {
            {-prompt}
            {-state}
            {-login_hint}
            {-domain_hint}
            {-code_challenge}
            {-code_challenge_method}
        } {
            #
            # Returns the URL for logging in
            #
            # "oauth2/authorize" is defined in RFC 6749, but requests
            # for MS id-tokens inversion v1.0 and v2.0 are defined
            # here:
            # https://learn.microsoft.com/en-us/azure/active-directory/develop/id-tokens
            #
            if {${:version} in {"" "v1.0"}} {
                set base https://login.microsoftonline.com/common/oauth2/authorize
            } else {
                #
                # When version "v2.0" is used, the concrete tenant
                # (i.e. not "common" as in the earlier version) has to
                # be specified, unless the MS application is
                # configured as a multi-tenant application.
                #
                set base https://login.microsoftonline.com/${:tenant}/oauth2/${:version}/authorize
            }

            set client_id ${:client_id}
            set scope ${:scope}
            set response_type ${:response_type}
            set nonce [::xo::oauth::nonce]
            set response_mode form_post
            set redirect_uri [:qualified ${:responder_url}]
            
            return [export_vars -no_empty -base $base {                
                client_id response_type redirect_uri response_mode
                state scope nonce prompt login_hint domain_hint
                code_challenge code_challenge_method                
            }]
        }

        :public method logout_url {
            {page ""}
        } {
            #
            # Returns the URL for logging out. After the logout, azure
            # redirects to the given page.
            #
            set base https://login.microsoftonline.com/common/oauth2/logout
            set post_logout_redirect_uri [:qualified $page]
            return [export_vars -no_empty -base $base {
                post_logout_redirect_uri
            }]
        }

        :public method logout {} {
            #
            # Perform logout operation form MS in the background
            # (i.e. without a redirect).
            #
            ns_http run [:logout_url]
        }

        :method get_user_data {
            -token
        } {
            #
            # Get data via the provided token (which comes from the
            # "id_token").  In case of an error or incomplete data,
            # add this information the result dict.
            #
            # See here for AD claim sets
            # https://learn.microsoft.com/en-us/azure/active-directory/develop/active-directory-optional-claims
            #
            # The error codes returned by Azure are defined here:
            # https://learn.microsoft.com/en-us/azure/active-directory/develop/reference-error-codes
            # Extra errors for OpenACS are prefixed with "oacs-"
            #
            # @return return a dict containing the extracted fields

            set result {}
            lassign [split $token .] jwt_header jwt_claims jwt_signature

            #ns_log notice "[self]: jwt_header <[:json_to_dict [encoding convertfrom "utf-8" [ns_base64decode -binary -- $jwt_header]]]>"

            if {$jwt_claims eq ""} {
                dict set result error [ns_queryget error]
                return $result
            }

            set claims [:json_to_dict \
                            [encoding convertfrom "utf-8" \
                                 [ns_base64decode -binary -- $jwt_claims]]]
            dict set result claims $claims

            set data [:get_required_fields \
                          -claims $claims \
                          -mapped_fields {
                              {upn email}
                              {family_name last_name}
                              {given_name first_names}
                          }]
            if {[dict exists $data error]} {
                set result [dict merge $data $result]
            } else {
                set result [dict merge $result [dict get $data fields]]
            }
            return $result
        }
    }

    #
    # Create in your ms_init.tcl script one or several authorizer
    # objects like the following (using defaults):
    #
    #   ms::Authorize create ms::azure
    #
    # or e.g.
    #
    #   ms::Authorize create ms::azure \
    #       -client-id ... \
    #       -login_failure_url / \
    #       -create_not_registered_users \
    #       -create_with_dotlrn_role "student"
    #
}

::xo::library source_dependent
#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 2
#    indent-tabs-mode: nil
# End

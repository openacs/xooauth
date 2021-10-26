::xo::library doc {
    Support for the Microsoft Graph API

    These interface classes support conversion from/to JavaScript and
    to the urlencoded calling patterns on the fly, just by specifying
    the Tcl variable names. Furthermore, the interface support
    pagination (some API calls return per default just a partial
    number of results (in MSGraph just the first 100 results), such
    that multiple REST calls have to be issued to get the full result
    set.

    To use this Microsoft Graph API, one has to create an "app", which
    must acquire an access token from the Microsoft identity
    platform. The access token contains information about your app and
    the permissions it has for the resources and APIs available
    through Microsoft Graph. To get an access token, your app must be
    registered with the Microsoft identity platform and be authorized
    by either a user or an administrator for access to the Microsoft
    Graph resources it needs.

    https://docs.microsoft.com/en-us/graph/auth/auth-concepts
    https://docs.microsoft.com/en-us/graph/auth-register-app-v2

    In theory, this API will allow later to switch to newer versions of
    the Graph API when newer versions (currently post 1.0) of the
    Microsoft Graph API will come out.

    @author Gustaf Neumann
}
::xo::library require rest-procs

namespace eval ::ms {

    ##################################################################################
    # Sample configuration for Microsoft Graph API
    #
    # #
    # # Define/override Ms parameters in section $server/ms
    # #
    # ns_section ns/server/$server/ms
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
        # see: https://docs.microsoft.com/en-us/azure/active-directory/develop/active-directory-v2-protocols
        #
        :property {tenant}

        :property {version v1.0}    ;# currently just used in URL generation

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

        :public method check_async_operation {location} {
            #ns_log notice "check_async_operation $location"

            if {![regexp {^/teams\('([^']+)'\)/operations\('([^']+)'\)$} $location . id opId]} {
                error "teams check_async_operation '$location' is not in the form of /teams({id})/operations({opId})"
            }

            set r [:request -method GET -token [:token] \
                       -url ${location}]

            #ns_log notice "/checkAsync GET Answer: $r"
            set status [dict get $r status]
            if {$status == 200} {
                set jsonDict [dict get $r JSON]
                ns_log notice "check_async_operation $location -> [dict get $jsonDict status]"
                return [dict get $jsonDict status]
            } elseif {$status == 404} {
                #
                # Well, it might be too early...
                #
                return NotFound
            }
            return $r
        }

        :method async_operation_status {{-wait:switch} r} {
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
                           count expand select filter orderby search}]]
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
                       -url /groups/${group_id}/members]
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
            set r [:request -method POST -token [:token] \
                       -url /teams/$team_id/archive?[:params {shouldSetSpoSiteReadOnlyForMembers}]]
            return [:async_operation_status -wait=$wait $r]
        }

        :public method "team create" {
            -description
            -displayName:required
            -visibility
            -owner:required
            {-wait:switch false}
        } {
            #
            # Create a new team.  A team owner must be provided when
            # creating a team in an application context.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/team-post
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
            return [:async_operation_status -wait=$wait $r]
        }

        :public method "team clone" {
            team_id
            -classification
            -description
            -displayName:required
            -mailNickname
            -partsToClone:required
            -visibility
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
            #
            # see https://docs.microsoft.com/en-us/graph/api/team-clone
            #
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
            return [:async_operation_status -wait=$wait $r]
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
            #
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
            {-wait:switch false}
        } {
            # Restore an archived team. This restores users' ability to
            # send messages and edit the team, abiding by tenant and
            # team settings. Teams are archived using the archive API.
            #
            # Details: https://docs.microsoft.com/en-us/graph/api/team-unarchive
            #
            set r [:request -method POST -token [:token] \
                       -url /teams/$team_id/unarchive]
            return [:async_operation_status -wait=$wait $r]
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
            #
            set r [:request -method GET -token [:token] \
                       -url /teams/${team_id}/members?[:params {select filter}]]
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
            #
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
            #
            set r [:request -method GET -token [:token] \
                       -url /users/$principal?[:params {select}]]
            return [:expect_status_code $r 200]
        }

        :public method "user list" {
            {-select "displayName,userPrincipalName,id"}
            {-filter ""}
            {-max_entries ""}
            {-top 100}
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
            #
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
            #
            set r [:request -method GET -token [:token] \
                       -url /users/${principal}/memberOf?[:params {
                           count filter orderby search}]]
            return [:expect_status_code $r 200]
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
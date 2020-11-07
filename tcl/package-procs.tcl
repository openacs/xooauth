::xo::library doc {
  OAuth

  @author Michael Aram
  @creation-date 2012

  Translation to XOTcl2:
  Gustaf Neumann
}

::xo::library require oauth-server-procs

namespace eval ::xo::oauth {

  ::xo::PackageMgr create Package \
      -superclass ::xo::Package \
      -table_name "xooauth_packages" \
      -pretty_name "OAuth" \
      -package_key "xooauth" \
      -parameter {
        {folder_id 0}
      } \
      -instmixin {::xo::oauth::Server ::xo::oauth::Client}

  Package instproc init {} {
    next
    set :folder_id [:require_root_folder \
                        -name "xooauth" \
                        -content_types {
                          ::xo::oauth::Credentials*
                          ::xo::oauth::ClientMetadata*
                          ::xo::oauth::ServerMetadata*
                        }]
    ::xo::db::CrClass get_instance_from_db -item_id ${:folder_id}
    set :delivery doc_return
    #my log [:serialize]
  }

  Package instproc index {} {
    set adp /packages/xooauth/lib/index
    set :mime_type text/html
    set package [self]
    :return_page -adp $adp -variables {
      package
    }
  }

  Package proc reset {} {
    # Convenience proc for development - delete all

    # ::xo::db::Class doesn't CASCADE on drop
    foreach object_type {
      ::xo::oauth::TempCredentials
      ::xo::oauth::TokenCredentials
      ::xo::oauth::ClientCredentials
      ::xo::oauth::Credentials
      ::xo::oauth::ClientMetadata
      ::xo::oauth::ServerMetadata
    } {
      set table_name [::xo::db::Class get_table_name -object_type $object_type]
      #my msg "set table_name ::xo::db::Class get_table_name -object_type $object_type -> $table_name"
      if { [catch {
        xo::dc dml [:qn delete_instances] "delete from $table_name"
        foreach ci [xo::dc list select_xoitems {
          select item_id from cr_items where content_type = :object_type
        }] {
          content::item::delete -item_id $ci
        }
        xo::dc dml [:qn drop_table] "drop table $table_name cascade"
        ::xo::db::sql::acs_object_type drop_type \
            -object_type $object_type -cascade_p t
      } fid] } {
        :msg "Error during delete:\n$fid"
      }
    }
    set p [::xo::oauth::Package initialize -url "/oauth"]
    ::xo::clusterwide ns_cache flush xotcl_object_type_cache root_folder-[$p id]
    ::content::folder::delete -folder_id [$p folder_id]

  }
  Package proc fill {} {
    set p [::xo::oauth::Package initialize -url "/oauth"]
    #$p require_server_metadata

    # Create Server MD for the "remote" server
    set sm [::xo::oauth::ServerMetadata new \
                -parent_id [$p folder_id] \
                -package_id [$p id] \
                -temp_credentials_url "http://shell.itec.km.co.at/oauth/initiate" \
                -token_credentials_url "http://shell.itec.km.co.at/oauth/token" \
                -authorization_url "http://shell.itec.km.co.at/oauth/authorize"]
    $sm save_new

    # Create a dummy client metadata record
    set cm [::xo::oauth::ClientMetadata new \
                -parent_id [$p folder_id] \
                -package_id [$p id] \
                -title "An Example OAuth Consumer Application" \
                -description "This is the description of the client application"]
    $cm save_new

    # Create a dummy client credentials record
    set ccc [::xo::oauth::ClientCredentials new \
                 -parent_id [$p folder_id] \
                 -package_id [$p id] \
                 -identifier "client1" \
                 -secret "123" \
                 -client_metadata_id [$cm item_id] \
                 -server_metadata_id [[$p server_metadata] item_id]]
    $ccc save_new

    return [$sm serialize]

  }


}

::xo::library source_dependent

#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 2
#    indent-tabs-mode: nil
# End:

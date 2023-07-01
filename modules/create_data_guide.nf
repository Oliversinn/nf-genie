
  // Create data guide
process create_data_guide {
    debug true
    container 'sagebionetworks/genie-data-guide:latest'
    secret 'SYNAPSE_AUTH_TOKEN'

    input:
    val previous
    val release
    val proj_id

    output:
    path "data_guide.pdf"

    script:
    """
    # cd /data_guide
    quarto render /data_guide/data_guide.qmd -P release:$release -P project_id:$proj_id --to pdf
    mv /data_guide/data_guide.pdf ./
    """
}
//   //
//   process syn_store {
//     debug true
//     container 'sagebionetworks/genie:latest'
//     secret 'SYNAPSE_AUTH_TOKEN'

//     input:
//     val release from ch_release
//     val proj_id from ch_project_id
//     path guide from data_guide_out

//     output:
//     stdout into syn_store_out

//     script:
//     """
//     #!/usr/bin/python3
//     from genie import extract
//     import synapseclient
//     syn = synapseclient.login()
//     config = extract.get_genie_config(syn=syn, project_id="$proj_id")
//     fileview = config['releaseFolder']
//     release_files = syn.tableQuery(f"select * from {fileview}")
//     release_files_df = release_files.asDataFrame()
//     if "$release" == "TEST.consortium":
//       release = "TESTING"
//     elif "$release" == "TEST.public":
//       release = "TESTpublic"
//     else:
//       release = "$release"
//     synid = release_files_df['id'][release_files_df.name == release].values[0]
//     syn.store(synapseclient.File("$guide", parentId=synid))
//     """
//   }
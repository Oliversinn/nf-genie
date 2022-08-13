#!/usr/bin/env nextflow

// parameters

// TODO: centers to process / exclude

// testing or production pipeline
params.production = false
// only run validation pipeline
params.only_validate = false
// to create new maf database
params.create_new_maf_db = false
// release name (pass in TEST.public to test the public release scripts)
params.release = "TEST.consortium"

// Determine which synapse id to pass into processing
if (params.production) {
  project_id = "syn3380222"
}
else {
  project_id = "syn7208886"
}
/*
release, seq
11-consortium, Jul-2021
12-consortium, Jan-2022
13-consortium, Jul-2022

11-public, Jan-2022
12-public, Jul-2022
13-public, Jan-2023
*/
def public_map = [
  "TEST": "Jan-2022",
  "11": "Jan-2022",
  "12": "Jul-2022",
  "13": "Jan-2023"
]
def consortium_map = [
  "TEST": "Jul-2022",
  "11": "Jul-2021",
  "12": "Jan-2022",
  "13": "Jul-2022"
]
release_split = params.release.tokenize('.')
major_release = release_split[0]

if (params.release.contains("public")) {
  seq_date = public_map[major_release]
}
else {
  seq_date = consortium_map[major_release]
}

ch_release = Channel.value(params.release)
ch_project_id = Channel.value(project_id)
ch_seq_date = Channel.value(seq_date)


/*
========================================================================================
    SETUP PROCESSES
========================================================================================
*/
if (params.only_validate) {

  // Validation for GENIE
  process validation {
    container 'sagebionetworks/genie:latest'
    secret 'SYNAPSE_AUTH_TOKEN'

    input:
    val proj_id from ch_project_id

    output:
    stdout into validation_out

    script:
    """
    python3 /root/Genie/bin/input_to_database.py \
    mutation \
    --project_id $proj_id \
    --onlyValidate \
    --genie_annotation_pkg \
    /root/annotation-tools
    """
  }
  validation_out.view()
}
else if (params.release.contains("public")) {
  // Only run consortium to public when not validate only and public
  process public_release {
    echo true
    container 'sagebionetworks/genie:latest'
    secret 'SYNAPSE_AUTH_TOKEN'

    input:
    val release from ch_release
    val seq from ch_seq_date

    output:
    stdout into public_release_out

    script:
    if (params.production) {
      """
      python3 /root/Genie/bin/consortium_to_public.py \
      $seq \
      /root/cbioportal \
      $release
      """
    }
    else {
      """
      python3 /root/Genie/bin/consortium_to_public.py \
      $seq \
      /root/cbioportal \
      $release \
      --test
      """
    }
  }
  public_release_out.view()

} else {
  // Only run processing pipline if not only validate and not public release
  // Split off creation of maf database
  // (This will simplify the genie pipeline)
  process maf_process {
    echo true
    container 'sagebionetworks/genie:latest'
    secret 'SYNAPSE_AUTH_TOKEN'

    input:
    val proj_id from ch_project_id

    output:
    stdout into maf_process_out

    script:
    if (params.create_new_maf_db) {
      """
      python3 /root/Genie/bin/input_to_database.py \
      mutation \
      --project_id $proj_id \
      --genie_annotation_pkg \
      /root/annotation-tools \
      --createNewMafDatabase
      """
    }
    else {
      """
      python3 /root/Genie/bin/input_to_database.py \
      mutation \
      --project_id $proj_id \
      --genie_annotation_pkg \
      /root/annotation-tools
      """
    }

  }
  maf_process_out.view()

  process main_process {
    echo true
    container 'sagebionetworks/genie:latest'
    secret 'SYNAPSE_AUTH_TOKEN'

    input:
    val proj_id from ch_project_id
    val previous from maf_process_out

    output:
    stdout into main_process_out

    script:
    """
    python3 /root/Genie/bin/input_to_database.py \
    main \
    --project_id $proj_id
    """
  }
  main_process_out.view()

  // Add consortium or public release flag
  process consortium_release {
    echo true
    container 'sagebionetworks/genie:latest'
    secret 'SYNAPSE_AUTH_TOKEN'

    input:
    val previous from main_process_out
    val release from ch_release
    val seq from ch_seq_date

    output:
    stdout into consortium_release_out

    script:
    if (params.production) {
      """
      python3 /root/Genie/bin/database_to_staging.py \
      $seq \
      /root/cbioportal \
      $release
      """
    }
    else {
      """
      python3 /root/Genie/bin/database_to_staging.py \
      $seq \
      /root/cbioportal \
      $release \
      --test
      """
    }
  }
  consortium_release_out.view()

  // Create release dashboard

  // Create data guide

  // Create skeleton release notes

  // run artifact finder
  // https://github.com/Sage-Bionetworks/GENIE-ArtifactFinder
  // TODO: Need to add staging ability for artifact finder
  process artifact_finder {
    container 'sagebionetworks/genie-artifact-finder'
    secret 'SYNAPSE_AUTH_TOKEN'

    when:
    params.production

    input:
    val previous from consortium_release_out
    val release from ch_release

    output:
    stdout into artifact_finder_out

    script:
    """
    python /artifact/artifact_finder.py $release
    """
  }
  artifact_finder_out.view()

  // copy consortium to BPC
  process consortium_to_bpc {
    container 'sagebionetworks/main-genie-release-utils'
    secret 'SYNAPSE_AUTH_TOKEN'

    when:
    params.production

    input:
    val previous from consortium_release_out
    val release from ch_release

    output:
    stdout into consortium_to_bpc_out

    script:
    """
    python3 consortium_to_bpc.py $release
    """
  }
  consortium_to_bpc_out.view()

  // check for any retractions in BPC
  process check_retraction {
    container 'sagebionetworks/main-genie-release-utils'
    secret 'SYNAPSE_AUTH_TOKEN'

    when:
    params.production

    input:
    val previous from consortium_release_out

    output:
    stdout into check_retraction_out

    script:
    """
    python3 check_bpc_retraction.py
    """
  }
  check_retraction_out.view()

  // TMB code
}

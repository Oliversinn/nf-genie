#!/usr/bin/env nextflow
// Ensure DSL2
nextflow.enable.dsl = 2

// IMPORT MODULES
include { check_for_retractions } from './modules/check_for_retractions'
include { create_consortium_release } from './modules/create_consortium_release'
include { create_data_guide } from './modules/create_data_guide'
include { create_public_release } from './modules/create_public_release'
include { find_maf_artifacts } from './modules/find_maf_artifacts'
// include { generate_tmb } from './modules/generate_tmb'
include { load_to_bpc } from './modules/load_to_bpc'
include { reset_processing } from './modules/reset_processing'
include { validate_data } from './modules/validate_data'
include { process_main } from './modules/process_main'
include { process_maf } from './modules/process_maf'

// SET PARAMETERS

// TODO: centers to process / exclude
// force start the pipeline, by resetting the center
// mapping annotation
// params.force = false
// Different process types (only_validate, main_process, maf_process, consortium_release, public_release)
params.process_type = "only_validate"
// Specify center
params.center = "ALL"
// to create new maf database
params.create_new_maf_db = false
// release name (pass in TEST.public to test the public release scripts)
params.release = "TEST.consortium"

// set defaults for docker image parameters
params.main_pipeline_docker = "sagebionetworks/genie:latest"
params.main_release_utils_docker = "sagebionetworks/main-genie-release-utils"
params.find_maf_artifacts_docker = "sagebionetworks/genie-artifact-finder"
params.create_data_guide_docker = "sagebionetworks/genie-data-guide"

// Validate input parameters
WorkflowMain.initialise(workflow, params, log)

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
  "13": "Jan-2023",
  "14": "Jul-2023",
  "15": "Jan-2024",
  "16": "Jul-2024",
  "17": "Jan-2025",
  "18": "Jul-2025",
  "19": "Jan-2026",
  "20": "Jul-2026"
]
def consortium_map = [
  "TEST": "Jul-2022",
  "11": "Jul-2021",
  "12": "Jan-2022",
  "13": "Jul-2022",
  "14": "Jan-2023",
  "15": "Jul-2023",
  "16": "Jan-2024",
  "17": "Jul-2024",
  "18": "Jan-2025",
  "20": "Jul-2025"
]
release_split = params.release.tokenize('.')
major_release = release_split[0]

if (params.release.contains("public")) {
  seq_date = public_map[major_release]
}
else {
  seq_date = consortium_map[major_release]
}
if (!seq_date) {
  throw new Exception("${major_release} release not supported in map variables in nf code.")
}

// If major release is not TEST
// Specify production synapse id to pass into processing
if (major_release != "TEST") {
  project_id = "syn3380222"
  center_map_synid = "syn10061452"
  is_prod = true
}
else {
  project_id = "syn7208886"
  center_map_synid = "syn11601248"
  is_prod = false
}

workflow {
  ch_release = Channel.value(params.release)
  ch_project_id = Channel.value(project_id)
  ch_seq_date = Channel.value(seq_date)
  ch_center = Channel.value(params.center)
  ch_is_prod = Channel.value(is_prod)

  // docker images
  ch_main_pipeline_docker = Channel.value(params.main_pipeline_docker)
  ch_main_release_utils_docker = Channel.value(params.main_release_utils_docker)
  ch_find_maf_artifacts_docker = Channel.value(params.find_maf_artifacts_docker)
  ch_create_data_guide_docker = Channel.value(params.create_data_guide_docker)

  // if (params.force) {
  //   reset_processing(center_map_synid)
  //   reset_processing.out.view()
  // }
  if (params.process_type == "only_validate") {
    validate_data(ch_project_id, ch_center, ch_main_pipeline_docker)
    // validate_data.out.view()
  } else if (params.process_type == "maf_process") {
    process_maf(ch_project_id, ch_center, params.create_new_maf_db, ch_main_pipeline_docker)
    // process_maf.out.view()
  } else if (params.process_type == "main_process") {
    process_main("default", ch_project_id, ch_center, ch_main_pipeline_docker)
  } else if (params.process_type == "consortium_release") {
    process_maf(ch_project_id, ch_center, params.create_new_maf_db, ch_main_pipeline_docker)
    process_main(process_maf.out, ch_project_id, ch_center, ch_main_pipeline_docker)
    create_consortium_release(process_main.out, ch_release, ch_is_prod, ch_seq_date, ch_main_pipeline_docker)
    create_data_guide(create_consortium_release.out, ch_release, ch_project_id, ch_create_data_guide_docker)
    load_to_bpc(create_data_guide.out, ch_release, ch_is_prod, ch_main_release_utils_docker)
    if (is_prod) {
      find_maf_artifacts(create_consortium_release.out, ch_release, ch_find_maf_artifacts_docker)
      check_for_retractions(create_consortium_release.out, ch_main_release_utils_docker)
    }
  } else if (params.process_type == "public_release") {
    create_public_release(ch_release, ch_seq_date, ch_is_prod, ch_main_pipeline_docker )
    create_data_guide(create_public_release.out, ch_release, ch_project_id, ch_create_data_guide_docker)
  } else {
    throw new Exception("process_type can only be 'only_validate', 'maf_process', 'main_process', 'consortium_release', 'public_release'")
  }
}

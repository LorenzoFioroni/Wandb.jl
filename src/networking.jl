
function _construct_new_run_mutation()
    return """
mutation UpsertBucket(\$project: String, \$entity: String, \$name: String!, \$state: String) {
    upsertBucket(input: {modelName: \$project, entityName: \$entity, name: \$name, state: \$state}) {
        bucket {
            project {
                name
                entity { name }
            }
            id
            name
        }
        inserted
    }
}
"""
end

function _construct_update_config_mutation()
    return """
mutation UpsertBucket(\$id: String!, \$config: JSONString!) {
    upsertBucket(input: {
        id: \$id,
        config: \$config
    }) {
        bucket {
            id
            config
        }
    }
}
"""
end

function _construct_upload_file_mutation()
    return """
    mutation CreateRunFiles(\$entity: String!, \$project: String!, \$run: String!, \$files: [String!]!) {
        createRunFiles(input: {
            entityName: \$entity,
            projectName: \$project,
            runName: \$run,
            files: \$files
        }) {
            runID
            uploadHeaders
            files {
                name
                uploadUrl
            }
        }
    }
    """
end

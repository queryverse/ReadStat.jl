# The schema/plain-text path: parse a SAS command file, SPSS command file,
# or Stata dictionary into a schema, then drive the fixed-width text parser
# with it.

export readstat_parse_sas_commands, readstat_parse_spss_commands,
    readstat_parse_stata_dictionary, readstat_parse_txt, readstat_schema_free

for schema_fn in (:readstat_parse_sas_commands, :readstat_parse_spss_commands,
                  :readstat_parse_stata_dictionary)
    @eval function $schema_fn(parser::ParserPtr, path::AbstractString, user_ctx,
                              out_error::Ref{ReadStatError})
        @ccall libreadstat.$schema_fn(parser::ParserPtr, path::Cstring, user_ctx::Any,
            out_error::Ref{ReadStatError})::SchemaPtr
    end
end

function readstat_parse_txt(parser::ParserPtr, path::AbstractString, schema::SchemaPtr, user_ctx)
    @ccall libreadstat.readstat_parse_txt(parser::ParserPtr, path::Cstring,
        schema::SchemaPtr, user_ctx::Any)::ReadStatError
end

function readstat_schema_free(schema::SchemaPtr)
    @ccall libreadstat.readstat_schema_free(schema::SchemaPtr)::Cvoid
end

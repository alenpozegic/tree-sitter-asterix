; extends

((fenced_code_block
  (info_string
    (language) @asterix_spec_fence)
  (code_fence_content) @injection.content)
  (#eq? @asterix_spec_fence "asterix-spec")
  (#set! injection.language "asterix_spec"))

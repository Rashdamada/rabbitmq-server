load(
    "@bazel_tools//tools/build_defs/repo:http.bzl",
    "http_archive",
)
load(
    "@rules_erlang//bzlmod:otp.bzl",
    "merge_archive",
)

def _installation_suffix(erlang_installation):
    wn = erlang_installation.workspace_name
    return wn.removeprefix("rules_erlang").removeprefix(".erlang_package.")

def _impl(ctx):
    elixir_archives = []
    for mod in ctx.modules:
        for release in mod.tags.elixir_github_release:
            name = "elixir_{}".format(release.version)
            url = "https://github.com/elixir-lang/elixir/archive/refs/tags/v{}.zip".format(release.version)
            props = {
                "name": name,
                "url": url,
                "strip_prefix": "elixir-{}".format(release.version),
                "sha256": release.sha256,
            }
            elixir_archives = merge_archive(props, elixir_archives)

    for props in elixir_archives:
        http_archive(
            build_file_content = ELIXIR_BUILD_FILE_CONTENT,
            **props
        )

elixir_github_release = tag_class(attrs = {
    "version": attr.string(),
    "sha256": attr.string(),
})

elixir = module_extension(
    implementation = _impl,
    tag_classes = {
        "elixir_github_release": elixir_github_release,
    },
)

ELIXIR_BUILD_FILE_CONTENT = """load(
    "@rabbitmq-server//bazel/elixir:elixir.bzl",
    "elixir_home",
)

elixir_home()
"""

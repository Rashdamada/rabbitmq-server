load(
    "@bazel_tools//tools/build_defs/repo:http.bzl",
    "http_archive",
)
load(
    "@rules_erlang//bzlmod:otp.bzl",
    "merge_archive",
)
load(
    "@rules_erlang//tools:erlang.bzl",
    "installation_suffix",
)

def _installation_suffix(erlang_installation):
    wn = erlang_installation.workspace_name
    return wn.removeprefix("rules_erlang").removeprefix(".erlang_package.")

def _impl(ctx):
    elixir_archives = []
    for mod in ctx.modules:
        for release in mod.tags.elixir_github_release:
            name = "elixir_{}_{}".format(
                release.version,
                _installation_suffix(release.erlang_installation),
            )
            url = "https://github.com/elixir-lang/elixir/archive/refs/tags/v{}.zip".format(release.version)
            props = {
                "name": name,
                "url": url,
                "strip_prefix": "foo",
                "sha256": release.sha256,
                "index": release.index,
                "erlang_installation": release.erlang_installation,
            }
            elixir_archives = merge_archive(props, elixir_archives)

    name_index_map = {props["name"]: props["index"] for props in elixir_archives}
    indexes = [props["index"] for props in elixir_archives]
    for i in range(len(indexes)):
        if indexes[i] != i:
            fail("elixir versions specified are not indexed properly: {}".format(name_index_map))

    for props in elixir_archives:
        index = props.pop("index")
        erlang_installation = props.pop("erlang_installation")
        http_archive(
            build_file_content = ELIXIR_BUILD_FILE_CONTENT.format(
                index = index,
                erlang_installation = erlang_installation,
            ),
            **props
        )

elixir_github_release = tag_class(attrs = {
    "version": attr.string(),
    "sha256": attr.string(),
    "index": attr.int(),
    "erlang_installation": attr.label(),
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

elixir_home(
    index = {index},
    erlang_installation = {erlang_installation},
)
"""

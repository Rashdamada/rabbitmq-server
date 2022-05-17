load(
    "@bazel_skylib//rules:common_settings.bzl",
    "BuildSettingInfo",
)
load(
    "@rules_erlang//tools:erlang_installation.bzl",
    "ErlangInstallationInfo",
    "erlang_dirs",
    "maybe_symlink_erlang",
)
load(
    "@rules_erlang//:erlang_app_info.bzl",
    "ErlangAppInfo",
)

ElixirBuildInfo = provider(
    doc = "A Home directory of a built Elixir",
    fields = ["release_dir", "elixir_home"],
)

def _impl(ctx):
    use_external_elixir = ctx.attr._use_external_elixir[BuildSettingInfo].value
    elixir_homes = ctx.attr._elixir_home[BuildSettingInfo].value
    if use_external_elixir and ctx.attr.index < len(elixir_homes):
        elixir_home = elixir_homes[ctx.attr.index]

        ebin = ctx.actions.declare_directory(path_join(ctx.attr.name, "ebin"))

        ctx.actions.run_shell(
            inputs = [],
            outputs = [ebin],
            command = "cp -R \"{elixir_home}\"/lib/elixir/ebin {ebin}".format(
                elixir_home = elixir_home,
                ebin = ebin.dirname,
            ),
        )

        return [
            DefaultInfo(
                files = depset([ebin]),
                runfiles = ctx.runfiles([ebin]),
            ),
            ElixirBuildInfo(
                release_dir = None,
                elixir_home = elixir_home,
            ),
            ErlangAppInfo(
                app_name = "elixir",
                include = [],
                beam = [ebin],
                priv = [],
                deps = [],
            ),
        ]
    else:
        # here build elixir
        return [
            DefaultInfo(),
            # ElixirBuildInfo(
            #     elixir_home = None,
            # ),
            # ErlangAppInfo(
            #     app_name = "elixir",
            #     include = [],
            #     beam = [ebin],
            #     priv = [],
            #     deps = [],
            # ),
        ]

elixir_build = rule(
    implementation = _impl,
    attrs = {
        "_use_external_elixir": attr.label(default = Label("//:use_external_elixir")),
        "_elixir_home": attr.label(default = Label("//:elixir_home")),
        "erlang_installation": attr.label(
            mandatory = True,
            providers = [ErlangInstallationInfo],
        ),
        "sources": attr.label_list(allow_files = True, mandatory = True),
        "index": attr.int(mandatory = True),
    },
)

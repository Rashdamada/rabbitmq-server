load(
    "@bazel_skylib//rules:common_settings.bzl",
    "BuildSettingInfo",
)
load(
    "@rules_erlang//tools:erlang_toolchain.bzl",
    "erlang_dirs",
    "maybe_symlink_erlang",
)
load(
    "@rules_erlang//:erlang_app_info.bzl",
    "ErlangAppInfo",
)
load(
    "@rules_erlang//:util.bzl",
    "path_join",
)

ElixirInfo = provider(
    doc = "A Home directory of a built Elixir",
    fields = ["elixir_home"],
)

def _impl(ctx):
    # here build elixir
    elixir_home = ctx.actions.declare_directory(ctx.label.name)
    ebin = ctx.actions.declare_directory("ebin")

    return [
        DefaultInfo(),
        ctx.toolchains["@rules_erlang//tools:toolchain_type"].otpinfo,
        ElixirInfo(
            # release_dir = None,
            elixir_home = ctx.attr.elixir_home,
        ),
        ErlangAppInfo(
            app_name = "elixir",
            include = [],
            beam = [ebin],
            priv = [],
            deps = [],
        ),
    ]

elixir_build = rule(
    implementation = _impl,
    attrs = {
        "sources": attr.label_list(allow_files = True, mandatory = True),
    },
    toolchains = ["@rules_erlang//tools:toolchain_type"],
)

def _elixir_external_impl(ctx):
    elixir_home = ctx.attr._elixir_home[BuildSettingInfo].value

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
        ctx.toolchains["@rules_erlang//tools:toolchain_type"].otpinfo,
        ElixirInfo(
            # release_dir = None,
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

elixir_external = rule(
    implementation = _elixir_external_impl,
    attrs = {
        "_elixir_home": attr.label(default = Label("//:elixir_home")),
    },
    toolchains = ["@rules_erlang//tools:toolchain_type"],
)

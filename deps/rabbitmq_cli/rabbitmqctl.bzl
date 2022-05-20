load(
    "@rules_erlang//:erlang_app_info.bzl",
    "ErlangAppInfo",
    "flat_deps",
)
load(
    "@rules_erlang//:util.bzl",
    "path_join",
)
load(
    "//bazel/elixir:elixir_toolchain.bzl",
    "elixir_dirs",
    "erlang_dirs",
    "maybe_symlink_erlang",
)

MIX_DEPS_DIR = "deps"

def _impl(ctx):
    escript = ctx.actions.declare_file(path_join("escript", "rabbitmqctl"))
    ebin = ctx.actions.declare_directory("ebin")

    copy_compiled_deps_commands = []
    copy_compiled_deps_commands.append("mkdir ${{MIX_INVOCATION_DIR}}/{}".format(MIX_DEPS_DIR))
    for dep in ctx.attr.deps:
        lib_info = dep[ErlangAppInfo]

        dest_dir = path_join("${MIX_INVOCATION_DIR}", MIX_DEPS_DIR, lib_info.app_name)
        copy_compiled_deps_commands.append(
            "mkdir {}".format(dest_dir),
        )
        copy_compiled_deps_commands.append(
            "mkdir {}".format(path_join(dest_dir, "include")),
        )
        copy_compiled_deps_commands.append(
            "mkdir {}".format(path_join(dest_dir, "ebin")),
        )
        for hdr in lib_info.include:
            copy_compiled_deps_commands.append(
                "cp ${{PWD}}/{source} {target}".format(
                    source = hdr.path,
                    target = path_join(dest_dir, "include", hdr.basename),
                ),
            )
        for beam in lib_info.beam:
            copy_compiled_deps_commands.append(
                "cp ${{PWD}}/{source} {target}".format(
                    source = beam.path,
                    target = path_join(dest_dir, "ebin", beam.basename),
                ),
            )

    mix_invocation_dir = ctx.actions.declare_directory("{}_mix".format(ctx.label.name))

    package_dir = ctx.label.package
    if ctx.label.workspace_root != "":
        package_dir = path_join(ctx.label.workspace_root, package_dir)

    (erlang_home, _, erlang_runfiles) = erlang_dirs(ctx)
    (elixir_home, elixir_runfiles) = elixir_dirs(ctx)

    script = """set -euo pipefail

{maybe_symlink_erlang}

if [[ "{elixir_home}" == /* ]]; then
    ABS_ELIXIR_HOME="{elixir_home}"
else
    ABS_ELIXIR_HOME=$PWD/{elixir_home}
fi

export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

export PATH="$ABS_ELIXIR_HOME"/bin:"{erlang_home}"/bin:${{PATH}}

MIX_INVOCATION_DIR="{mix_invocation_dir}"

cp -R ${{PWD}}/{package_dir}/config ${{MIX_INVOCATION_DIR}}/config
# cp -R ${{PWD}}/{package_dir}/include ${{MIX_INVOCATION_DIR}}/include # rabbitmq_cli's include directory is empty
cp -R ${{PWD}}/{package_dir}/lib ${{MIX_INVOCATION_DIR}}/lib
cp    ${{PWD}}/{package_dir}/mix.exs ${{MIX_INVOCATION_DIR}}/mix.exs

{copy_compiled_deps_command}

cd ${{MIX_INVOCATION_DIR}}
export HOME=${{PWD}}
export DEPS_DIR={mix_deps_dir}

# mix can error on windows regarding permissions for a symlink at this path
# deps/rabbitmq_cli/rabbitmqctl_mix/_build/dev/lib/rabbit_common/ebin
# so instead we'll try skip that
mkdir -p _build/dev/lib/rabbit_common
mkdir _build/dev/lib/rabbit_common/include
cp ${{DEPS_DIR}}/rabbit_common/include/* \\
    _build/dev/lib/rabbit_common/include
mkdir _build/dev/lib/rabbit_common/ebin
cp ${{DEPS_DIR}}/rabbit_common/ebin/* \\
    _build/dev/lib/rabbit_common/ebin

export ERL_COMPILER_OPTIONS=deterministic
"$ABS_ELIXIR_HOME"/bin/mix local.hex --force
"$ABS_ELIXIR_HOME"/bin/mix local.rebar --force
"$ABS_ELIXIR_HOME"/bin/mix make_all_in_src_archive

cd ${{OLDPWD}}
cp ${{MIX_INVOCATION_DIR}}/escript/rabbitmqctl {escript_path}

mkdir -p {ebin_dir}
mv ${{MIX_INVOCATION_DIR}}/_build/dev/lib/rabbitmqctl/ebin/* {ebin_dir}
mv ${{MIX_INVOCATION_DIR}}/_build/dev/lib/rabbitmqctl/consolidated/* {ebin_dir}

rm -dR ${{MIX_INVOCATION_DIR}}
mkdir ${{MIX_INVOCATION_DIR}}
touch ${{MIX_INVOCATION_DIR}}/placeholder
    """.format(
        maybe_symlink_erlang = maybe_symlink_erlang(ctx),
        erlang_home = erlang_home,
        elixir_home = elixir_home,
        mix_invocation_dir = mix_invocation_dir.path,
        package_dir = package_dir,
        copy_compiled_deps_command = "\n".join(copy_compiled_deps_commands),
        mix_deps_dir = MIX_DEPS_DIR,
        escript_path = escript.path,
        ebin_dir = ebin.path,
    )

    inputs = depset(
        direct = ctx.files.srcs,
        transitive = [
            erlang_runfiles.files,
            elixir_runfiles.files,
        ] + [
            depset(dep[ErlangAppInfo].include + dep[ErlangAppInfo].beam)
            for dep in ctx.attr.deps
        ],
    )

    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [escript, ebin, mix_invocation_dir],
        command = script,
        mnemonic = "MIX",
    )

    deps = flat_deps(ctx.attr.deps)

    runfiles = ctx.runfiles([ebin])
    runfiles = runfiles.merge_all(
        [
            erlang_runfiles,
            elixir_runfiles,
            ctx.runfiles(ctx.toolchains["//bazel/elixir:toolchain_type"].erlangapp.beam),
        ] + [
            dep[DefaultInfo].default_runfiles
            for dep in deps
        ],
    )

    return [
        DefaultInfo(
            executable = escript,
            files = depset([ebin]),
            runfiles = runfiles,
        ),
        ErlangAppInfo(
            app_name = ctx.attr.name,
            include = [],
            beam = [ebin],
            priv = [],
            deps = deps,
        ),
    ]

rabbitmqctl_private = rule(
    implementation = _impl,
    attrs = {
        "is_windows": attr.bool(mandatory = True),
        "srcs": attr.label_list(allow_files = True),
        "deps": attr.label_list(providers = [ErlangAppInfo]),
    },
    toolchains = [
        "//bazel/elixir:toolchain_type",
    ],
    executable = True,
)

def rabbitmqctl(**kwargs):
    rabbitmqctl_private(
        is_windows = select({
            "@bazel_tools//src/conditions:host_windows": True,
            "//conditions:default": False,
        }),
        **kwargs
    )

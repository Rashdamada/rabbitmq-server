load(
    ":elixir_build.bzl",
    "elixir_build",
)
load(
    ":elixir_toolchain.bzl",
    "elixir_toolchain",
)

def elixir_home(version):
    [major, minor, _] = version.split(".")

    elixir_build(
        name = "elixir",
        sources = native.glob(
            ["**/*"],
            exclude = ["BUILD.bazel", "WORKSPACE.bazel"],
        ),
    )

    elixir_toolchain(
        name = "elixir_linux",
        elixir = ":elixir",
    )

    native.toolchain(
        name = "elixir_linux_toolchain",
        # exec_compatible_with = [
        #     "//:elixir_external",
        # ],
        target_compatible_with = [
            "@rabbitmq-server//:elixir_{}_{}".format(major, minor),
        ],
        toolchain = ":elixir_linux",
        toolchain_type = "@rabbitmq-server//bazel/elixir:toolchain_type",
        visibility = ["//visibility:public"],
    )

class ClickhouseAT2111 < Formula
  desc "Free analytics DBMS for big data with SQL interface"
  homepage "https://clickhouse.com"
  url "https://github.com/ClickHouse/ClickHouse.git",
    tag:      "v21.11.6.7-stable",
    revision: "534b23949e0ce94f645aa61a8e52f4dd24ef82d6"
  license "Apache-2.0"
  head "https://github.com/ClickHouse/ClickHouse.git",
    branch:   "21.11"

  bottle do
    root_url "https://github.com/Altinity/homebrew-clickhouse/releases/download/clickhouse@21.11-21.11.6.7"
    rebuild 1
    sha256 cellar: :any_skip_relocation, arm64_monterey: "ac9d02d28f3e593afaa9585d8cb6dfa18c7a83a42a0b8e5e7f7840c4b32a509c"
    sha256                               monterey:       "1c8ea3e754a7acb3927e6d5152bf8556a4e5d33baa8ba923da5361e34ddeb90c"
  end

  depends_on "cmake" => :build
  depends_on "gawk" => :build
  depends_on "gettext" => :build
  depends_on "libtool" => :build
  depends_on "ninja" => :build
  depends_on "perl" => :build
  depends_on "python@3.9" => :build

  on_macos do
    depends_on "llvm" => :build
  end

  on_linux do
    depends_on "llvm"
  end

  def install
    cmake_args = std_cmake_args.dup

    # It is crucial that CMake config scripts see RelWithDebInfo as a build type,
    # since the code is only handling it (and Debug) properly.
    # It is OK if Homebrew infrastructure filters out the debug info-related flags later.
    cmake_args.reject! { |x| x.start_with?("-DCMAKE_BUILD_TYPE=") }
    cmake_args << "-DCMAKE_BUILD_TYPE=RelWithDebInfo"

    # Vanilla Clang is the only officially supported compiler.
    cmake_args << "-DCMAKE_C_COMPILER=#{Formula["llvm"].bin}/clang"
    cmake_args << "-DCMAKE_CXX_COMPILER=#{Formula["llvm"].bin}/clang++"
    cmake_args << "-DCMAKE_AR=#{Formula["llvm"].bin}/llvm-ar"
    cmake_args << "-DCMAKE_RANLIB=#{Formula["llvm"].bin}/llvm-ranlib"
    cmake_args << "-DOBJCOPY_PATH=#{Formula["llvm"].bin}/llvm-objcopy"

    # Disable more stuff that is irrelevant for production builds.
    cmake_args << "-DENABLE_CCACHE=OFF"
    cmake_args << "-DSANITIZE=OFF"
    cmake_args << "-DENABLE_TESTS=OFF"
    cmake_args << "-DENABLE_CLICKHOUSE_TEST=OFF"

    system "cmake", "-S", ".", "-B", "./build", "-G", "Ninja", *cmake_args
    system "cmake", "--build", "./build", "--config", "RelWithDebInfo", "--target", "clickhouse", "--parallel"

    system "./build/programs/clickhouse", "install", "--prefix", HOMEBREW_PREFIX, "--binary-path", prefix/"bin",
      "--user", "", "--group", ""

    # Relax the permissions when packaging.
    Dir.glob([
      etc/"clickhouse-server/**/*",
      var/"run/clickhouse-server/**/*",
      var/"log/clickhouse-server/**/*",
    ]) do |file|
      chmod 0664, file
      chmod "a+x", file if File.directory?(file)
    end
  end

  def post_install
    # Fix the permissions when deploying.
    Dir.glob([
      etc/"clickhouse-server/**/*",
      var/"run/clickhouse-server/**/*",
      var/"log/clickhouse-server/**/*",
    ]) do |file|
      chmod 0640, file
      chmod "ug+x", file if File.directory?(file)
    end

    # Make sure the data directories are initialized.
    system opt_bin/"clickhouse", "start", "--prefix", HOMEBREW_PREFIX, "--binary-path", opt_bin, "--user", ""
    system opt_bin/"clickhouse", "stop", "--prefix", HOMEBREW_PREFIX
  end

  def caveats
    <<~EOS
      If you intend to run ClickHouse server:

        - Familiarize yourself with the usage recommendations:
            https://clickhouse.com/docs/en/operations/tips/

        - Increase the maximum number of open files limit in the system:
            macOS: https://clickhouse.com/docs/en/development/build-osx/#caveats
            Linux: man limits.conf

        - Set the 'net_admin', 'ipc_lock', and 'sys_nice' capabilities on #{opt_bin}/clickhouse binary. If the capabilities are not set the taskstats accounting will be disabled. You can enable taskstats accounting by setting those capabilities manually later.
            Linux: sudo setcap 'cap_net_admin,cap_ipc_lock,cap_sys_nice+ep' #{opt_bin}/clickhouse

        - By default, the pre-configured 'default' user has an empty password. Consider setting a real password for it:
            https://clickhouse.com/docs/en/operations/settings/settings-users/

        - By default, ClickHouse server is configured to listen for local connections only. Adjust 'listen_host' configuration parameter to allow wider range of addresses for incoming connections:
            https://clickhouse.com/docs/en/operations/server-configuration-parameters/settings/#server_configuration_parameters-listen_host
    EOS
  end

  service do
    run [
      opt_bin/"clickhouse", "server",
      "--config-file", etc/"clickhouse-server/config.xml",
      "--pid-file", var/"run/clickhouse-server/clickhouse-server.pid"
    ]
    keep_alive true
    run_type :immediate
    working_dir var
    log_path var/"log/clickhouse-server/stdout.log"
    error_log_path var/"log/clickhouse-server/stderr.log"
  end

  test do
    assert_match "Denis Glazachev",
      shell_output("#{bin}/clickhouse local --query 'SELECT * FROM system.contributors FORMAT TabSeparated'")
  end
end

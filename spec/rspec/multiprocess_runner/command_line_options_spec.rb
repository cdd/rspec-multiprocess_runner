require 'spec_helper'
require 'rspec/multiprocess_runner/command_line_options'

module RSpec::MultiprocessRunner
  describe CommandLineOptions do
    let(:error_stream) { StringIO.new }
    let(:parsed) { CommandLineOptions.new.parse(arguments, error_stream) }

    describe '#parse' do
      shared_examples "the default timeout time and number of processes" do
        it "uses 3 processes" do
          expect(parsed.worker_count).to eq(3)
        end

        it "has no per-file timeout" do
          expect(parsed.file_timeout_seconds).to be_nil
        end

        it "has a 15 second per-example timeout" do
          expect(parsed.example_timeout_seconds).to eq(15)
        end
      end

      shared_examples "no errors" do
        it "has no errors" do
          parsed
          expect(error_stream.string).to eq("")
        end
      end

      describe "by default" do
        let(:arguments) { [] }

        include_examples "the default timeout time and number of processes"
        include_examples "no errors"

        it "has no files or directories" do
          expect(parsed.explicit_files_or_directories).to be_nil
        end

        it "has looks for spec files only" do
          expect(parsed.pattern).to eq("**/*_spec.rb")
        end

        it "has no RSpec options" do
          expect(parsed.rspec_options).to eq([])
        end
      end

      describe "with some filenames only" do
        let(:arguments) {
          %w(spec/foo_spec.rb spec/mod/quux_spec.rb)
        }

        it "has those files" do
          expect(parsed.explicit_files_or_directories).to eq(arguments)
        end

        include_examples "the default timeout time and number of processes"
        include_examples "no errors"
      end

      describe "with options" do
        let(:arguments) { %w(-w 12 --file-timeout 1200 --example-timeout 67 --first-is-1 --use-given-order) }

        it "has the process count" do
          expect(parsed.worker_count).to eq(12)
        end

        it "has the file timeout time" do
          expect(parsed.file_timeout_seconds).to eq(1200)
        end

        it "has the example timeout time" do
          expect(parsed.example_timeout_seconds).to eq(67)
        end

        it "has the first-is-1 flag" do
          expect(parsed.first_is_1).to be_truthy
        end

        it "has no files" do
          expect(parsed.explicit_files_or_directories).to be_nil
        end

        it "has the use-given-order flag" do
          expect(parsed.use_given_order).to be_truthy
        end

        include_examples "no errors"
      end

      describe "with a pattern option" do
        let(:arguments) { %w(--pattern a*_spec.rb) }

        it "has the pattern" do
          expect(parsed.pattern).to eq("a*_spec.rb")
        end

        it "has no files" do
          expect(parsed.explicit_files_or_directories).to be_nil
        end

        include_examples "no errors"
      end

      describe 'with a log failing files option' do
        let(:arguments) { %w(--log-failing-files logfile.name) }

        it 'has the file name' do
          expect(parsed.log_failing_files).to eq("logfile.name")
        end

        it "has no files" do
          expect(parsed.explicit_files_or_directories).to be_nil
        end

        include_examples "no errors"
      end

      describe "with only RSpec pass-through options" do
        let(:arguments) { %w(-- --backtrace -c) }

        it "has the RSpec options" do
          expect(parsed.rspec_options).to eq(%w(--backtrace -c))
        end

        include_examples "the default timeout time and number of processes"
        include_examples "no errors"
      end

      describe "with RSpec options and files and everything" do
        let(:arguments) {
          %w(
            --worker-count 8
            -t 250
            -T 3.1
            spec/models/ear_spec.rb
            spec/helpers
            --
            -r spec/support/special_helper.rb
            --backtrace
          )
        }

        it "has the process count" do
          expect(parsed.worker_count).to eq(8)
        end

        it "has the file timeout" do
          expect(parsed.file_timeout_seconds).to eq(250)
        end

        it "has the example timeout" do
          expect(parsed.example_timeout_seconds).to eq(3.1)
        end

        it "has the files" do
          expect(parsed.explicit_files_or_directories).to eq(
            %w(spec/models/ear_spec.rb spec/helpers)
          )
        end

        it "has the RSpec options" do
          expect(parsed.rspec_options).to eq(
            %w(-r spec/support/special_helper.rb --backtrace)
          )
        end
      end

      describe "with an unknown option" do
        let(:arguments) { %w(-X) }

        before do
          parsed
        end

        it "prints an error" do
          expect(error_stream.string).to match(/invalid.*-X/)
        end

        it "prints the help" do
          expect(error_stream.string).to match(/file-timeout SECONDS/)
        end

        it "returns nil (to signal the user process to exit)" do
          expect(parsed).to be_nil
        end
      end

      describe "when the help is requested" do
        let(:arguments) { %w(--help) }

        it "prints the help" do
          parsed
          expect(error_stream.string).to match(/file-timeout SECONDS/)
        end

        it "returns nil (to signal the user process to exit)" do
          expect(parsed).to be_nil
        end
      end

      describe 'with environment overrides' do
        let(:arguments) { [] }

        describe 'for worker count' do
          it 'obeys PARALLEL_TEST_PROCESSORS' do
            stub_env('PARALLEL_TEST_PROCESSORS', '7')
            expect(parsed.worker_count).to eq(7)
          end

          it 'obeys MULTIRSPEC_WORKER_COUNT' do
            stub_env('MULTIRSPEC_WORKER_COUNT', '22')
            expect(parsed.worker_count).to eq(22)
          end

          it 'prefers MULTIRSPEC_WORKER_COUNT to PARALLEL_TEST_PROCESSORS' do
            stub_env('PARALLEL_TEST_PROCESSORS', '7')
            stub_env('MULTIRSPEC_WORKER_COUNT', '21')
            expect(parsed.worker_count).to eq(21)
          end

          describe 'with an explicit worker count CLI option' do
            let(:arguments) { %w(--worker-count 9) }

            it 'uses that value instead of either env var' do
              stub_env('PARALLEL_TEST_PROCESSORS', '7')
              stub_env('MULTIRSPEC_WORKER_COUNT', '21')
              expect(parsed.worker_count).to eq(9)
            end
          end
        end

        describe 'for first-is-1' do
          %w(PARALLEL_TEST_FIRST_IS_1 MULTIRSPEC_FIRST_IS_1).each do |var|
            %w(true 1).each do |val|
              it "treats #{var}=#{val.inspect} as set" do
                stub_env(var, val)
                expect(parsed.first_is_1).to be_truthy
              end
            end

            %w(false 0).each do |val|
              it "treats #{var}=#{val.inspect} as not set" do
                stub_env(var, val)
                expect(parsed.first_is_1).to be_falsey
              end
            end
          end
        end
      end
    end

    describe "#files_to_run" do
      let(:tmpdir) { Pathname.new(File.expand_path('../../../tmp', __FILE__)) }
      let(:actual_files) { parsed.files_to_run }

      around do |example|
        tmpdir.rmtree if tmpdir.exist?
        tmpdir.mkpath
        FileUtils.cd(tmpdir.to_s) do
          example.run
        end
      end

      def touch(path)
        pathname =
          case path
          when Pathname
            path
          else
            Pathname.new(path.to_s)
          end

        pathname.open('w') { |f| }
      end

      before do
        touch(tmpdir + "README.md")
        tmpdir.join("spec").tap do |spec_dir|
          spec_dir.mkpath
          touch(spec_dir + "spec_helper.rb")
        end
        tmpdir.join("spec/jobs").tap do |job_dir|
          job_dir.mkpath
          ("aa".."cz").each { |pfx| touch(job_dir.join("#{pfx}_job_spec.rb")) }
        end
        tmpdir.join("spec/models").tap do |models_dir|
          models_dir.mkpath
          ("aa".."cz").each { |pfx| touch(models_dir.join("#{pfx}_spec.rb")) }
        end
        tmpdir.join("features").tap do |features_dir|
          features_dir.mkpath
          ("aa".."cz").each { |pfx| touch(features_dir.join("#{pfx}_spec.rb")) }
          touch(features_dir + "spec_helper.rb")
        end
      end

      after do
        tmpdir.rmtree if tmpdir.exist?
      end

      describe "without a pattern or any files" do
        let(:arguments) { [] }

        it 'is all spec files' do
          expect(actual_files.size).to eq(3 * 3 * 26)
          expect(actual_files).to include('features/ae_spec.rb')
          expect(actual_files).to include('spec/jobs/bt_job_spec.rb')
        end

        it 'does not contain non-spec files' do
          expect(actual_files).not_to include('spec/spec_helper.rb')
          expect(actual_files).not_to include('README.md')
        end
      end

      describe "with some explicit files" do
        let(:arguments) { %w(features/cd_spec.rb spec/jobs/aj_job_spec.rb) }

        it 'is only the files noted' do
          expect(actual_files).to eq(arguments.sort)
        end
      end

      describe "with explicit files, some of which do not exist" do
        let(:arguments) { %w(features/az_spec.rb features/dn_spec.rb README.md) }

        it "is only the files that exist" do
          expect(actual_files).to eq(%w(features/az_spec.rb README.md))
        end
      end

      describe "with some explicit directories" do
        let(:arguments) { %w(spec/jobs features) }

        it 'is all spec files in those directories' do
          expect(actual_files).to include('spec/jobs/bl_job_spec.rb')
          expect(actual_files).to include('features/ae_spec.rb')
          expect(actual_files.size).to eq(2 * 3 * 26)
        end

        it 'does not include non-spec files' do
          expect(actual_files).not_to include('features/spec_helper.rb')
        end

        it 'does not include specs from other directories' do
          expect(actual_files).not_to include('spec/models/cj_spec.rb')
        end
      end

      describe "with a pattern only" do
        let(:arguments) { %w(--pattern **/?k_*spec.rb) }

        it 'includes only files that match the pattern' do
          expect(actual_files).to eq(%w(
            features/ak_spec.rb
            features/bk_spec.rb
            features/ck_spec.rb
            spec/jobs/ak_job_spec.rb
            spec/jobs/bk_job_spec.rb
            spec/jobs/ck_job_spec.rb
            spec/models/ak_spec.rb
            spec/models/bk_spec.rb
            spec/models/ck_spec.rb
          ))
        end
      end

      describe "with a pattern and a directory" do
        let(:arguments) { %w(--pattern **/?t_*spec.rb features) }

        it 'includes only files that match the pattern in the directory' do
          expect(actual_files).to eq(%w(
            features/at_spec.rb
            features/bt_spec.rb
            features/ct_spec.rb
          ))
        end
      end
    end
  end
end

# Repository policy checks complement actionlint's workflow syntax validation.
require 'yaml'

directory = ARGV.fetch(0)
files = Dir.glob(File.join(directory, '*.{yml,yaml}')).sort
abort 'CI policy: expected only check.yml and test.yml' unless files.map { |f| File.basename(f) } == %w[check.yml test.yml]

def require_policy(condition, file, message)
  abort "CI policy: #{File.basename(file)}: #{message}" unless condition
end

files.each do |file|
  text = File.read(file)
  data = YAML.safe_load(text)
  require_policy(data.is_a?(Hash), file, 'expected workflow mapping')
  require_policy(data['permissions'] == { 'contents' => 'read' }, file, 'token must be contents: read')
  events = data['on'] || data[true] # macOS system Ruby uses YAML 1.1.
  require_policy(events.is_a?(Hash) && events.keys.sort == %w[pull_request push workflow_dispatch], file, 'unexpected workflow trigger')
  require_policy(events['push'] == { 'branches' => %w[main dev] }, file, 'push must be branch-only, without tags')
  require_policy(!text.match?(/secrets\s*[.\[]|github\s*\.\s*token|id-token\s*:/i), file, 'credentials or identity token are prohibited')
  jobs = data['jobs']
  require_policy(jobs.is_a?(Hash) && !jobs.empty?, file, 'expected jobs')
  jobs.each_value do |job|
    require_policy(!job.key?('permissions') || job['permissions'] == { 'contents' => 'read' }, file, 'job escalates permissions')
    require_policy(!job.key?('uses') && !job.key?('secrets') && !job.key?('environment'), file, 'deployment or reusable job is prohibited')
    require_policy(job['timeout-minutes'].is_a?(Integer) && job['timeout-minutes'].between?(1, 60), file, 'job needs a bounded timeout')
    steps = job['steps']
    require_policy(steps.is_a?(Array) && !steps.empty?, file, 'expected steps')
    steps.each do |step|
      if step.key?('uses')
        require_policy(step['uses'].match?(/\Aactions\/(checkout|setup-go)@[0-9a-f]{40}\z/), file, 'action must be approved and SHA-pinned')
        if step['uses'].start_with?('actions/checkout@')
          require_policy(step.fetch('with', {})['persist-credentials'] == false, file, 'checkout must not persist credentials')
        end
      end
      command = step.fetch('run', '')
      require_policy(!command.match?(/\bgh\s+(release|api)|\bgit\s+push|\b(?:npm|cargo)\s+publish|\bbrew\s+bump/i), file, 'publishing command is prohibited')
    end
  end
end
puts 'Fork CI policy passed: read-only, branch/PR/manual checks, no publisher.'

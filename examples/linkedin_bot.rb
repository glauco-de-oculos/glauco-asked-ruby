# frozen_string_literal: true

require_relative "../core/framework/glauco-framework"

LINKEDIN_URL =
  "https://www.linkedin.com/jobs/collections/recommended/?currentJobId=4400463179"

module GlaucoBrowserProfile
  def self.configure!(
    profile_name: "default",
    root_dir: File.join(Dir.home, ".glauco", "profiles")
  )
    profile_dir = File.expand_path(
      File.join(root_dir, profile_name, "webview2")
    )

    FileUtils.mkdir_p(profile_dir)

    Display.setAppName(APP_NAME)

    System.setProperty(
      "org.eclipse.swt.browser.DefaultType",
      "edge"
    )

    System.setProperty(
      "org.eclipse.swt.browser.EdgeDataDir",
      profile_dir
    )

    profile_dir
  end
end

profile_dir = GlaucoBrowserProfile.configure!(
  profile_name: "linkedin",
  root_dir: File.expand_path("../.glauco_profiles", __dir__)
)

puts "[Glauco] Perfil persistente do navegador:"
puts profile_dir

app = GlaucoAgentBrowserEnv.new(visible: true)

app.run_ui do
  app.shell.setText("Glauco - LinkedIn Jobs")
  app.shell.setSize(1280, 820)
end

app.open_url(LINKEDIN_URL)

closed = false

listener_class = Class.new do
  include org.eclipse.swt.widgets.Listener

  def initialize(callback)
    @callback = callback
  end

  def handleEvent(_event)
    @callback.call
  end
end

app.run_ui do
  app.shell.addListener(
    org.eclipse.swt.SWT::Dispose,
    listener_class.new(proc { closed = true })
  )
end

sleep 0.2 until closed
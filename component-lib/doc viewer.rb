require_relative '../core/framework/glauco-framework'
require 'webrick'
require 'cgi'
require 'fileutils'


class DocViewer < Component
  @@server_started = false
  @@server_port = 8080
  @@public_dir = File.join(Dir.pwd, "public")

  def initialize(parent_renderer:)
    super(parent_renderer: parent_renderer)
    @doc_path = nil

    # Garante que a pasta pública exista
    FileUtils.mkdir_p(@@public_dir)

    # Sobe o servidor HTTP apenas uma vez
    unless @@server_started
      Thread.new do
        server = WEBrick::HTTPServer.new(
          Port: @@server_port,
          DocumentRoot: @@public_dir,
          AccessLog: [],
          Logger: WEBrick::Log.new(nil, 0)
        )
        trap("INT") { server.shutdown }
        server.start
      end
      @@server_started = true
    end

    define_render do
      div(style: "padding:20px") do
        # Botão de upload
        button(on_click: proc {
          dialog = FileDialog.new(@parent_renderer.browser.get_shell, SWT::OPEN)
          dialog.set_filter_extensions(["*.pdf", "*.docx", "*.xlsx", "*.pptx"])
          path = dialog.open
          if path
            filename = File.basename(path)
            dest = File.join(@@public_dir, filename)
            FileUtils.cp(path, dest)
            @doc_path = filename
            @parent_renderer.render
          end
        }) { "Selecionar arquivo" } +

        # Renderização condicional
        if @doc_path
          ext = File.extname(@doc_path).downcase
          url = "http://localhost:#{@@server_port}/#{@doc_path}"

          if ext == ".pdf"
            iframe(src: url, style: "width:100%;height:400px;")
          else
            office_url = "https://view.officeapps.live.com/op/embed.aspx?src=#{CGI.escape(url)}"
            iframe(src: office_url, style: "width:100%;height:400px;")
          end
        else
          span("Nenhum documento selecionado")
        end
      end
    end
  end
end

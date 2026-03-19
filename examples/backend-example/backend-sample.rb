require_relative 'glauco-framework'
require_relative 'backend_service'

include Frontend
include BackendService

class BuscaUsuario < Component
  def initialize(parent_renderer:)
    super(parent_renderer: parent_renderer)

    @state[:user] = nil
    @state[:loading] = false
    @state[:input] = ""

    define_render do
      div(style: "padding:20px; font-family:sans-serif") do
        
        # Campo de entrada
        input(
          type: "text",
          placeholder: "ID do usuário...",
          value: @state[:input],
          oninput: proc { |val|
            set_state(:input, val)
          }
        ) +


        # Loading
        bind(:loading, p) { |l|
          l ? "Consultando backend..." : ""
        } +

        # Resultado
        bind(:user, div) do |u|
          next "" unless u
          <<~HTML
            <h3>Resultado:</h3>
            <p>ID: #{u[:id]}</p>
            <p>Nome: #{u[:nome]}</p>
            <p>Status: #{u[:premium] ? "Premium" : "Normal"}</p>
          HTML
        end
      end
    end
  end

  def carregar_usuario(id)
    set_state(:loading, true)

    run_ui do
      begin
        usuario = BackendService.buscar_usuario(id)
        async do
          set_state(:user, usuario)
          set_state(:loading, false)
        end
      rescue => e
        async do
          set_state(:user, { id: id, nome: "Erro", premium: false })
          set_state(:loading, false)
        end
      end
    end
  end
end


# Render
app = BuscaUsuario.new(parent_renderer: $root)
$root.root_component = app
$root.render

$shell.setSize(600, 400)
$shell.open

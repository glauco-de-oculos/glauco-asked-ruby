require_relative '../core/framework/glauco-framework'

include Frontend

# Componente de chat integrado ao LLM (simples)
class ChatApp < Component
  def initialize(parent_renderer:)
    super(parent_renderer: parent_renderer)
    @state[:messages] = []
    @state[:input] = ""

    @agent = GlaucoAgentBrowserEnv.new

    define_render do
      div(style: "padding:20px; font-family:sans-serif;") do
        h2 { "Chat com LLM" } +

        # Lista de mensagens
        bind(:messages, div(style: "border:1px solid #ccc; padding:10px; height:400px; overflow:auto;") ) do |msgs|
          (msgs || []).map { |m| "<p><b>#{m[:from]}:</b> #{m[:text]}</p>" }.join
        end +

        # Caixa de texto
        bind( :input, span ) do |input_value| 
            input(type: "text", style: "width:80%; padding:8px; margin-top:10px;",
                value: input_value,
                onblur: proc { |v| set_state(:input, v) }
            ) 
        end +

        # Botão enviar
        button(style: "padding:10px; margin-left:10px;",
          onclick: proc {
            user_msg = @state[:input]
            next if user_msg.strip.empty?

            # adiciona msg do usuário
            msgs = @state[:messages]
            msgs << { from: "Você", text: user_msg }
            set_state(:messages, msgs)
            set_state(:input, "")

            # chama o LLM em thread
            Thread.new do
                resposta = @agent.interpretar(user_msg)

                async do
                    msgs = @state[:messages]
                    msgs << { from: "LLM", text: resposta }
                    set_state(:messages, msgs)
                end
            end

            nil   
          }
        ) { "Enviar" }
      end
    end
  end

  # Função mock para simular chamada ao LLM.
  # Substituir por API real!
  def chamar_llm(texto)
    "Resposta gerada pelo modelo para: #{texto}"
  end
end

# Inicialização do app
app = ChatApp.new(parent_renderer: $root)
$root.root_component = app
$root.render

$shell.setSize(900, 700)
$shell.open

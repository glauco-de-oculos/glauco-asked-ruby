# frozen_string_literal: true
# Glauco Licitações: instalação inicial em sliding steps
# Versão integrada ao Glauco Framework por caminho relativo, servida pelo Frontend HTTP e usando Carbon Web Components.
# Corrige inicialização direta do servidor Frontend sem depender do cockpit global do framework.

# Carrega o Glauco Framework por caminho relativo ao arquivo atual.
# Estrutura esperada quando este arquivo estiver em examples/:
#   core/framework/glauco-framework.rb
#   examples/glauco_instalacao_inicial_relative_framework.rb

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

FRAMEWORK_RELATIVE_CANDIDATES = [
  File.expand_path('../core/framework/glauco-framework', __dir__),
  File.expand_path('../core/framework/glauco-framework.rb', __dir__),
  File.expand_path('./core/framework/glauco-framework', __dir__),
  File.expand_path('./core/framework/glauco-framework.rb', __dir__),
  File.expand_path('../../core/framework/glauco-framework', __dir__),
  File.expand_path('../../core/framework/glauco-framework.rb', __dir__)
].uniq.freeze

unless defined?(SWT) && defined?(Display) && defined?(Shell) && defined?(Browser) && defined?(BrowserFunction)
  framework_path = FRAMEWORK_RELATIVE_CANDIDATES.find do |path|
    File.exist?(path) || File.exist?("#{path}.rb")
  end

  unless framework_path
    raise LoadError, "Glauco Framework não encontrado por caminho relativo. Caminhos testados:\n#{FRAMEWORK_RELATIVE_CANDIDATES.join("\n")}"
  end

  require framework_path.sub(/\.rb\z/, '')
end

require 'json'
require 'fileutils'
require 'time'
require 'cgi'
require 'tmpdir'

unless defined?(SWT) && defined?(Display) && defined?(Shell) && defined?(Browser) && defined?(BrowserFunction)
  raise LoadError, 'O Glauco Framework foi carregado, mas os aliases SWT necessários não ficaram disponíveis: SWT, Display, Shell, Browser e BrowserFunction.'
end

# Classes adicionais usadas pelo instalador. Não carrega jar; só cria aliases JRuby
# para classes que já estão disponíveis porque o framework importou o SWT.
java_import 'org.eclipse.swt.widgets.DirectoryDialog' unless defined?(DirectoryDialog)
java_import 'org.eclipse.swt.layout.GridLayout' unless defined?(GridLayout)
java_import 'org.eclipse.swt.layout.GridData' unless defined?(GridData)

module GlaucoInstaller
  APP_DIR = File.join(Dir.home, '.glauco-licitacoes')
  CONFIG_PATH = File.join(APP_DIR, 'installer-state.json')
  DEFAULT_WORKSPACE = if Gem.win_platform?
                        File.join(Dir.home, 'AppData', 'Roaming', 'glauco-licitacoes-electron', 'workspace')
                      else
                        File.join(Dir.home, '.local', 'share', 'glauco-licitacoes', 'workspace')
                      end

  def self.deep_merge(a, b)
    a.merge(b) { |_k, old_v, new_v| old_v.is_a?(Hash) && new_v.is_a?(Hash) ? deep_merge(old_v, new_v) : new_v }
  end

  def self.default_state
    {
      'version' => 1,
      'created_at' => Time.now.iso8601,
      'updated_at' => Time.now.iso8601,
      'workspace_path' => DEFAULT_WORKSPACE,
      'enterprise' => {
        'razao_social' => '',
        'nome_fantasia' => '',
        'cnpj' => '',
        'inscricao_estadual' => '',
        'inscricao_municipal' => '',
        'cnae_principal' => '',
        'cidade' => '',
        'uf' => 'BA',
        'endereco' => '',
        'representante_legal' => '',
        'cpf_representante' => '',
        'telefone' => '',
        'email' => '',
        'teto_financeiro' => '',
        'diretriz' => '',
        'objetos_preferenciais' => ''
      },
      'google' => { 'operator_email' => '', 'status' => 'pendente', 'last_confirmed_at' => nil },
      'whatsapp' => { 'number' => '', 'status' => 'pendente', 'last_confirmed_at' => nil },
      'installation' => { 'completed' => false, 'completed_at' => nil }
    }
  end

  def self.load_state
    FileUtils.mkdir_p(APP_DIR)
    return default_state unless File.exist?(CONFIG_PATH)

    deep_merge(default_state, JSON.parse(File.read(CONFIG_PATH, encoding: 'UTF-8')))
  rescue StandardError
    default_state
  end

  def self.save_state(state)
    state['updated_at'] = Time.now.iso8601
    FileUtils.mkdir_p(APP_DIR)
    File.write(CONFIG_PATH, JSON.pretty_generate(state), encoding: 'UTF-8')

    workspace = state['workspace_path'].to_s.strip
    return if workspace.empty?

    FileUtils.mkdir_p(workspace)
    FileUtils.mkdir_p(File.join(workspace, 'documentos'))
    FileUtils.mkdir_p(File.join(workspace, 'propostas'))
    FileUtils.mkdir_p(File.join(workspace, 'logs'))
    File.write(File.join(workspace, 'setup.json'), JSON.pretty_generate(state), encoding: 'UTF-8')
  end

  class MethodMissingTags < BasicObject
    VOID_TAGS = %i[area base br col embed hr img input link meta param source track wbr].freeze

    def self.render(&block)
      builder = new
      builder.instance_eval(&block)
      builder.to_s
    end

    def initialize
      @out = +''
    end

    def to_s
      @out
    end

    def doctype
      @out << '<!doctype html>'
    end

    def raw(value)
      @out << value.to_s
    end

    def text(value)
      @out << ::CGI.escapeHTML(value.to_s)
    end

    def tag(name, *args, **attrs, &block)
      content = args.first
      name = if defined?(::CarbonRegistry)
               ::CarbonRegistry.resolve(name).to_s
             else
               name.to_s.tr('_', '-')
             end
      @out << "<#{name}#{attrs_to_s(attrs)}>"

      unless VOID_TAGS.include?(name.to_sym)
        if block
          instance_eval(&block)
        elsif !content.nil?
          text(content)
        end
        @out << "</#{name}>"
      end

      nil
    end

    def method_missing(name, *args, **attrs, &block)
      tag(name, *args, **attrs, &block)
    end

    def respond_to_missing?(_name, _include_private = false)
      true
    end

    private

    def attrs_to_s(attrs)
      return '' if attrs.nil? || attrs.empty?

      attrs.map do |key, value|
        next if value.nil? || value == false
        html_key = key.to_s.tr('_', '-')
        value == true ? " #{html_key}" : " #{html_key}=\"#{::CGI.escapeHTML(value.to_s)}\""
      end.compact.join
    end
  end

  CSS = <<~CSS
    :root{--bg:#07111f;--cds-background:#07111f;--cds-layer:#0b1626;--cds-layer-accent:#0f2036;--cds-field:#081322;--cds-border-subtle:#30425f;--cds-text-primary:#edf5ff;--cds-text-secondary:#9fb0c5;--cds-link-primary:#78a9ff;--panel:#0b1626cc;--panel2:#0e1d31e8;--line:#24324a;--text:#edf5ff;--muted:#9fb0c5;--blue:#1a66ff;--blue2:#00a3ff;--cyan:#4de3ff;--green:#6ee7b7;--yellow:#facc15;--danger:#fb7185}
    *{box-sizing:border-box}html,body{margin:0;height:100%;overflow:hidden;font-family:Inter,Segoe UI,Arial,sans-serif;background:var(--bg);color:var(--text)}
    body:before,body:after{content:"";position:fixed;inset:auto;filter:blur(58px);opacity:.7;animation:float 9s ease-in-out infinite alternate;pointer-events:none}
    body:before{width:560px;height:560px;left:-130px;top:-120px;background:radial-gradient(circle,#1a66ff 0,#0a7cff 36%,transparent 70%)}
    body:after{width:470px;height:470px;right:10%;bottom:-160px;background:radial-gradient(circle,#00ffd5 0,#0c3d63 42%,transparent 72%);animation-duration:12s}
    @keyframes float{from{transform:translate3d(-18px,8px,0) scale(1)}to{transform:translate3d(34px,-30px,0) scale(1.08)}}
    .app{height:100%;display:grid;grid-template-columns:300px 1fr;position:relative;z-index:1;background:linear-gradient(116deg,#07111fee 0%,#091827f2 44%,#0a1220ee 100%)}
    .rail{position:relative;padding:28px 30px;border-right:1px solid #1d2a40;background:linear-gradient(168deg,#062fff 0%,#0b61ff 46%,#07111f 47%,#07111f 100%);overflow:hidden}
    .rail:after{content:"";position:absolute;right:-80px;top:-5%;width:210px;height:112%;background:#07111f;transform:rotate(-8deg);transform-origin:center}
    .brand{position:relative;z-index:2;font-weight:800;letter-spacing:.02em}.brand small{display:block;margin-top:8px;color:#d8e7ff;font-weight:500}
    .steps-list{position:absolute;z-index:2;left:30px;bottom:36px;right:36px;display:grid;gap:10px}.step-mini{font-size:12px;color:#d4e1f3;display:flex;gap:8px;align-items:center}.dot{width:8px;height:8px;border-radius:999px;background:#6582b1}.step-mini.active .dot{background:white;box-shadow:0 0 0 5px #ffffff22}.step-mini.done .dot{background:var(--green)}
    .main{display:grid;grid-template-rows:64px 1fr 92px;min-width:0}.top{display:flex;align-items:center;justify-content:space-between;padding:0 32px;border-bottom:1px solid #1a2638;color:#bfd0e6}.top b{color:#fff}.top .tag{font-size:12px;text-transform:uppercase;letter-spacing:.16em;color:#8ba2bd}
    .viewport{overflow:hidden;position:relative}.slider{height:100%;display:flex;transition:transform .42s cubic-bezier(.22,.8,.2,1)}.slide{min-width:100%;height:100%;padding:54px 58px;display:grid;align-content:center}.slide.grid{grid-template-columns:minmax(420px,620px) minmax(320px,1fr);gap:44px;align-items:center}.eyebrow{font-size:13px;text-transform:uppercase;letter-spacing:.13em;color:#88a6c8;margin-bottom:16px}h1{font-size:44px;line-height:1.03;margin:0 0 20px;font-weight:650;letter-spacing:-.035em}p{font-size:16px;line-height:1.55;color:#bcc9db;margin:0 0 22px}.card{background:linear-gradient(180deg,#0f2036db,#0b1727db);border:1px solid #263650;box-shadow:0 24px 70px #00000042;border-radius:20px;padding:22px}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}.metric{border:1px solid #2b3d5a;background:#0b1627bb;border-radius:14px;padding:16px}.metric label{display:block;color:#91a5bf;font-size:11px;text-transform:uppercase;letter-spacing:.08em}.metric strong{display:block;margin-top:8px;font-size:15px;color:white;word-break:break-word}.form{display:grid;grid-template-columns:1fr 1fr;gap:14px}.field.full{grid-column:1/-1}label{display:block;color:#a8bdd5;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.08em;margin-bottom:6px}cds-text-input,cds-textarea{width:100%;--cds-field:#081322;--cds-field-02:#081322;--cds-text-primary:#f7fbff;--cds-text-secondary:#a8bdd5;--cds-border-strong:#30425f;--cds-focus:#4aa3ff}cds-button{max-width:none}.card cds-button{width:100%}input,textarea{width:100%;background:#081322;border:1px solid #30425f;color:#f7fbff;border-radius:10px;padding:13px 14px;font-size:14px;outline:none}textarea{min-height:94px;resize:none}input:focus,textarea:focus{border-color:#4aa3ff;box-shadow:0 0 0 3px #1a66ff2a}.status{margin-top:14px;border-left:4px solid var(--yellow);background:#101b2b;padding:12px 14px;color:#f4f7fb;border-radius:8px}.status.ok{border-color:var(--green)}.status.err{border-color:var(--danger)}.webbox{height:520px;border:1px solid #2b3e5d;border-radius:18px;background:#081321;overflow:hidden;display:grid;place-items:center;color:#92a6c0;padding:18px}.webbox b{color:white}.footer{display:flex;align-items:center;justify-content:flex-end;gap:18px;padding:0 32px;border-top:1px solid #1a2638;background:#07111fdc}.btn{border:1px solid #314461;background:#0d1a2c;color:white;border-radius:10px;padding:13px 22px;min-width:110px;font-weight:700;cursor:pointer}.btn.primary{background:linear-gradient(90deg,#1a66ff,#0f8cff);border-color:#1a66ff}.btn:disabled{opacity:.4;cursor:not-allowed}.progress{display:flex;gap:8px}.bar{width:36px;height:4px;border-radius:9px;background:#31435e}.bar.active,.bar.done{background:#1a66ff}.workspace{display:flex;gap:12px}.workspace input{flex:1}.callout{border:1px solid #2b3d5a;background:#0b1627cc;border-radius:16px;padding:18px;color:#c6d2e2}.callout h3{margin:0 0 10px}.bullets{display:grid;gap:10px}.bullets div{padding-left:16px;border-left:3px solid #1a66ff;color:#c8d5e6}.finish-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}
  CSS

  JS = <<~JS
    const initialState = __STATE__;
    const steps = [
      {key:'platform', tag:'Plataforma', title:'Configuração inicial'},
      {key:'enterprise', tag:'Cadastro empresarial', title:'Empresa'},
      {key:'gmail', tag:'Google e email', title:'Gmail'},
      {key:'whatsapp', tag:'WhatsApp', title:'Canal operacional'},
      {key:'manual', tag:'Objetivos', title:'Funcionamento'},
      {key:'workspace', tag:'Pasta de trabalho', title:'Workspace'},
      {key:'finish', tag:'Concluir', title:'Finalização'}
    ];
    let index = 0;
    let state = JSON.parse(JSON.stringify(initialState));
    const $ = s => document.querySelector(s);
    const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    function callNative(name, payload){
      try { return window[name](JSON.stringify(payload || {})); }
      catch(e){ console.warn(name, e); return null; }
    }
    function save(patch){
      const result = callNative('glaucoSave', patch);
      if(result){ try { state = JSON.parse(result); } catch(_){} }
      render();
    }
    function setPath(obj, path, value){
      const parts = path.split('.');
      const last = parts.pop();
      let cur = obj;
      for(const p of parts){ cur[p] ||= {}; cur = cur[p]; }
      cur[last] = value;
    }
    function getPath(path){ return path.split('.').reduce((o,k)=>o && o[k], state) || ''; }
    function formInput(path, label, placeholder='', full=false, textarea=false){
      const val = getPath(path);
      const id = 'f_' + path.replaceAll('.','_');
      const klass = full ? 'field full' : 'field';
      const safeLabel = esc(label);
      const safePlaceholder = esc(placeholder);
      const safeVal = esc(val);
      if(textarea){
        return `<div class="${klass}"><cds-textarea id="${id}" data-path="${path}" label="${safeLabel}" placeholder="${safePlaceholder}" value="${safeVal}">${safeVal}</cds-textarea></div>`;
      }
      return `<div class="${klass}"><cds-text-input id="${id}" data-path="${path}" label="${safeLabel}" value="${safeVal}" placeholder="${safePlaceholder}"></cds-text-input></div>`;
    }
    function platform(){ return `<section class="slide"><div class="eyebrow">IA para licitações do estado</div><h1>Organize a empresa para competir melhor nas licitações da Bahia.</h1><p>A instalação prepara o estado inicial da empresa, os canais de autenticação, a pasta de trabalho e o contexto que será usado pelo cockpit operacional.</p><div class="cards"><div class="metric"><label>Pasta local</label><strong>${esc(state.workspace_path)}</strong></div><div class="metric"><label>Radar diário</label><strong>Corpus Bahia + agente Gemini</strong></div><div class="metric"><label>Canais</label><strong>Tela, email e WhatsApp</strong></div></div></section>`; }
    function enterprise(){ return `<section class="slide"><div class="eyebrow">Perfil jurídico e operacional</div><h1>Cadastre a empresa e defina o recorte financeiro inicial.</h1><p>Esses dados alimentam documentos, propostas, filtros de aderência e alertas de risco financeiro.</p><div class="card"><div class="form">${formInput('enterprise.razao_social','Razão social','Empresa LTDA')}${formInput('enterprise.nome_fantasia','Nome fantasia','Nome comercial')}${formInput('enterprise.cnpj','CNPJ','00.000.000/0001-00')}${formInput('enterprise.teto_financeiro','Teto financeiro','R$ 85.000,00')}${formInput('enterprise.inscricao_estadual','Inscrição estadual','Isento ou número')}${formInput('enterprise.inscricao_municipal','Inscrição municipal','Número municipal')}${formInput('enterprise.cnae_principal','CNAE principal','Ex.: 42.13-8-00')}${formInput('enterprise.cidade','Cidade','Salvador')}${formInput('enterprise.uf','UF','BA')}${formInput('enterprise.email','Email institucional','contato@empresa.com')}${formInput('enterprise.telefone','Telefone','+55 71 99999-9999')}${formInput('enterprise.representante_legal','Representante legal','Nome completo')}${formInput('enterprise.cpf_representante','CPF representante','000.000.000-00')}${formInput('enterprise.endereco','Endereço completo','Rua, número, bairro, CEP',true)}${formInput('enterprise.objetos_preferenciais','Objetos preferenciais','Obras, infraestrutura, manutenção, fornecimento...',true,true)}${formInput('enterprise.diretriz','Diretriz operacional','Como o agente deve filtrar e explicar oportunidades',true,true)}</div></div></section>`; }
    function gmail(){ return `<section class="slide grid"><div><div class="eyebrow">Identidade e email</div><h1>Vincule uma conta Google para o operador principal.</h1><p>O email identifica o operador, registra atividade, recebe alertas e serve como canal de acompanhamento das oportunidades.</p><div class="card"><div class="form">${formInput('google.operator_email','Email Google','operador@empresa.com',true)}</div><cds-button data-action="gmail" style="margin-top:14px;width:100%">Confirmar Google/Gmail</cds-button><div class="status ${state.google.status==='confirmado'?'ok':''}">${state.google.status==='confirmado'?'Google/Gmail confirmado':'Aguardando login'}</div></div></div><div class="webbox"><div><b>Painel interno de Google/Gmail</b><p>O login abre na webview nativa à direita da aplicação. Credenciais não são lidas pelo instalador.</p></div></div></section>`; }
    function whatsapp(){ return `<section class="slide grid"><div><div class="eyebrow">Notificação operacional</div><h1>Ative WhatsApp para receber oportunidades e pendências.</h1><p>O canal será usado para alertas, pendências documentais, status de proposta e avisos de editais aderentes.</p><div class="card"><div class="form">${formInput('whatsapp.number','Número WhatsApp','+55 71 99999-9999',true)}</div><cds-button data-action="whatsapp" style="margin-top:14px;width:100%">Confirmar WhatsApp</cds-button><div class="status ${state.whatsapp.status==='confirmado'?'ok':''}">${state.whatsapp.status==='confirmado'?'WhatsApp registrado / pareado':'Aguardando pareamento'}</div></div></div><div class="webbox"><div><b>Painel interno de WhatsApp Web</b><p>Use o QR Code quando a webview carregar o WhatsApp Web. Se houver bloqueio de compatibilidade, o número fica registrado para pareamento posterior.</p></div></div></section>`; }
    function manual(){ return `<section class="slide"><div class="eyebrow">Objetivos operacionais</div><h1>Como a plataforma passa a operar depois da instalação.</h1><div class="callout"><div class="bullets"><div><b>Cadastro → Documentos.</b> A empresa passa a ter um estado inicial com CNPJ, responsáveis, teto financeiro e pasta de trabalho.</div><div><b>Documentos → Validação.</b> Certidões, DFL, CATs e vínculos técnicos são anexados, lidos e classificados por função.</div><div><b>Radar → Proposta.</b> Editais da Bahia são comparados contra perfil, documentos, valor e aderência operacional.</div><div><b>Revisão → Dossiê.</b> A proposta só deve ser usada externamente após conferência humana dos dados formais.</div></div></div></section>`; }
    function workspace(){ return `<section class="slide"><div class="eyebrow">Pasta de trabalho</div><h1>Escolha onde o sistema salvará estado, documentos e propostas.</h1><p>A pasta será usada como workspace local. O instalador cria subpastas para documentos, propostas e logs.</p><div class="card"><label>Pasta de trabalho</label><div class="workspace"><cds-text-input id="workspace_path" value="${esc(state.workspace_path)}" label="Pasta local" style="flex:1"></cds-text-input><cds-button kind="secondary" data-action="pick">Escolher pasta</cds-button></div><div class="status ok">O arquivo setup.json será salvo nesta pasta ao finalizar.</div></div></section>`; }
    function finish(){ return `<section class="slide"><div class="eyebrow">Concluir</div><h1>Revise os dados principais e finalize a instalação.</h1><div class="finish-grid"><div class="metric"><label>Empresa</label><strong>${esc(state.enterprise.razao_social || 'Não informada')}</strong></div><div class="metric"><label>Google</label><strong>${esc(state.google.status)}</strong></div><div class="metric"><label>WhatsApp</label><strong>${esc(state.whatsapp.status)}</strong></div></div><div class="callout" style="margin-top:16px">Ao finalizar, o instalador salva o estado local e deixa o cockpit pronto para abrir com a empresa, canais e workspace já definidos.</div></section>`; }
    const renderers = {platform, enterprise, gmail, whatsapp, manual, workspace, finish};
    function syncFields(){ document.querySelectorAll('[data-path]').forEach(el=>setPath(state, el.dataset.path, el.value ?? '')); const ws=$('#workspace_path'); if(ws) state.workspace_path=ws.value ?? ''; }
    function render(){
      $('#slider').innerHTML = steps.map(s=>renderers[s.key]()).join('');
      $('#slider').style.transform = `translateX(${-index*100}%)`;
      $('#screenTag').textContent = steps[index].tag;
      $('#screenTitle').textContent = steps[index].title;
      $('#backBtn').disabled = index===0;
      $('#nextBtn').textContent = index===steps.length-1 ? 'Finalizar instalação' : 'Continuar';
      $('#progress').innerHTML = steps.map((_,i)=>`<span class="bar ${i===index?'active':i<index?'done':''}"></span>`).join('');
      $('#miniSteps').innerHTML = steps.map((s,i)=>`<div class="step-mini ${i===index?'active':i<index?'done':''}"><span class="dot"></span>${s.tag}</div>`).join('');
      callNative('glaucoStepChanged', { step: steps[index].key });
    }
    document.addEventListener('input', e=>{ const el = e.target.closest ? e.target.closest('[data-path], #workspace_path') : e.target; if(el && (el.dataset.path || el.id==='workspace_path')) syncFields(); });
    document.addEventListener('cds-text-input-input', syncFields);
    document.addEventListener('cds-textarea-input', syncFields);
    document.addEventListener('click', e=>{
      const node = e.target.closest ? e.target.closest('[data-action]') : e.target;
      const a = node && node.dataset ? node.dataset.action : null;
      if(a==='gmail'){ syncFields(); save({google:{operator_email:state.google.operator_email,status:'confirmado',last_confirmed_at:new Date().toISOString()}}); callNative('glaucoNavigateWebview',{kind:'gmail'}); }
      if(a==='whatsapp'){ syncFields(); save({whatsapp:{number:state.whatsapp.number,status:'confirmado',last_confirmed_at:new Date().toISOString()}}); callNative('glaucoNavigateWebview',{kind:'whatsapp'}); }
      if(a==='pick'){ const path = callNative('glaucoPickFolder',{current:state.workspace_path}); if(path){ state.workspace_path=path; save({workspace_path:path}); } }
    });
    $('#backBtn').onclick=()=>{ syncFields(); save(state); if(index>0){index--; render();} };
    $('#nextBtn').onclick=()=>{ syncFields(); save(state); if(index<steps.length-1){index++; render();} else { callNative('glaucoFinish', state); } };
    render();
  JS

  HTML = MethodMissingTags.render do
    doctype
    html(lang: 'pt-BR') do
      head do
        meta(charset: 'utf-8')
        meta(name: 'viewport', content: 'width=device-width, initial-scale=1')
        base(href: defined?(::Frontend) ? "#{::Frontend.base_url}/" : '/')
        title('Glauco Licitações — Instalação inicial')
        raw(::CarbonRegistry.style_tag) if defined?(::CarbonRegistry)
        raw(::CarbonRegistry.script_tag) if defined?(::CarbonRegistry)
        raw(::CarbonRegistry.defined_style_tag) if defined?(::CarbonRegistry)
        style { raw CSS }
      end
      body do
        div(class: 'app') do
          aside(class: 'rail') do
            div(class: 'brand') do
              text 'Instalação inicial'
              small('Glauco Licitações')
            end
            div(class: 'steps-list', id: 'miniSteps')
          end
          main(class: 'main') do
            header(class: 'top') do
              span(class: 'tag', id: 'screenTag') { text 'Plataforma' }
              b(id: 'screenTitle') { text 'Configuração inicial' }
            end
            section(class: 'viewport') { div(class: 'slider', id: 'slider') }
            footer(class: 'footer') do
              cds_button('Voltar', kind: 'secondary', id: 'backBtn')
              div(class: 'progress', id: 'progress')
              cds_button('Continuar', id: 'nextBtn')
            end
          end
        end
        script { raw JS }
      end
    end
  end

  class SaveFunction < BrowserFunction
    def initialize(browser, name, app)
      super(browser, name)
      @app = app
    end

    def function(args)
      patch = args && args[0] ? JSON.parse(args[0].to_s) : {}
      @app.state = GlaucoInstaller.deep_merge(@app.state, patch)
      GlaucoInstaller.save_state(@app.state)
      JSON.generate(@app.state)
    rescue StandardError => e
      JSON.generate({ 'error' => e.message })
    end
  end

  class PickFolderFunction < BrowserFunction
    def initialize(browser, name, app)
      super(browser, name)
      @app = app
    end

    def function(_args)
      dialog = DirectoryDialog.new(@app.shell, SWT::OPEN)
      dialog.setText('Escolher pasta de trabalho')
      dialog.setFilterPath(@app.state['workspace_path'].to_s) if @app.state['workspace_path']
      dialog.open
    end
  end

  class WebviewFunction < BrowserFunction
    def initialize(browser, name, app)
      super(browser, name)
      @app = app
    end

    def function(args)
      payload = args && args[0] ? JSON.parse(args[0].to_s) : {}
      case payload['kind']
      when 'gmail'
        @app.web_browser.setUrl('https://accounts.google.com/ServiceLogin?service=mail&continue=https%3A%2F%2Fmail.google.com%2Fmail%2F')
      when 'whatsapp'
        @app.web_browser.setUrl('https://web.whatsapp.com/')
      else
        @app.render_web_placeholder('Aguardando etapa')
      end
      'ok'
    end
  end

  class StepFunction < BrowserFunction
    def initialize(browser, name, app)
      super(browser, name)
      @app = app
    end

    def function(args)
      payload = args && args[0] ? JSON.parse(args[0].to_s) : {}
      case payload['step']
      when 'gmail'
        @app.web_browser.setUrl('https://accounts.google.com/ServiceLogin?service=mail&continue=https%3A%2F%2Fmail.google.com%2Fmail%2F')
      when 'whatsapp'
        @app.web_browser.setUrl('https://web.whatsapp.com/')
      else
        @app.render_web_placeholder(payload['step'].to_s)
      end
      'ok'
    end
  end

  class FinishFunction < BrowserFunction
    def initialize(browser, name, app)
      super(browser, name)
      @app = app
    end

    def function(args)
      final_state = args && args[0] ? JSON.parse(args[0].to_s) : @app.state
      @app.state = GlaucoInstaller.deep_merge(@app.state, final_state)
      @app.state['installation']['completed'] = true
      @app.state['installation']['completed_at'] = Time.now.iso8601
      GlaucoInstaller.save_state(@app.state)
      message = "Instalação finalizada. Estado salvo em: #{CONFIG_PATH}"
      @app.ui_browser.execute("alert(#{JSON.generate(message)});")
      'ok'
    rescue StandardError => e
      @app.ui_browser.execute("alert(#{JSON.generate("Erro ao finalizar: #{e.message}")});")
      'error'
    end
  end

  class App
    attr_reader :shell, :ui_browser, :web_browser
    attr_accessor :state

    def initialize
      @state = GlaucoInstaller.load_state
      @display = Display.new
      @shell = Shell.new(@display)
      @shell.setText('Glauco Licitações — Instalação inicial')
      @shell.setSize(1600, 900)

      layout = GridLayout.new(2, false)
      layout.marginWidth = 0
      layout.marginHeight = 0
      layout.horizontalSpacing = 0
      @shell.setLayout(layout)

      @ui_browser = Browser.new(@shell, SWT::EDGE | SWT::BORDER)
      ui_data = GridData.new(SWT::FILL, SWT::FILL, true, true)
      ui_data.widthHint = 1040
      @ui_browser.setLayoutData(ui_data)

      @web_browser = Browser.new(@shell, SWT::EDGE | SWT::BORDER)
      web_data = GridData.new(SWT::FILL, SWT::FILL, false, true)
      web_data.widthHint = 560
      @web_browser.setLayoutData(web_data)

      SaveFunction.new(@ui_browser, 'glaucoSave', self)
      PickFolderFunction.new(@ui_browser, 'glaucoPickFolder', self)
      WebviewFunction.new(@ui_browser, 'glaucoNavigateWebview', self)
      StepFunction.new(@ui_browser, 'glaucoStepChanged', self)
      FinishFunction.new(@ui_browser, 'glaucoFinish', self)
    end

    def render_web_placeholder(label)
      safe = label.to_s.gsub(/[<>&]/, '')
      html = MethodMissingTags.render do
        doctype
        html do
          head do
            meta(charset: 'utf-8')
            base(href: defined?(::Frontend) ? "#{::Frontend.base_url}/" : '/')
            raw(::CarbonRegistry.style_tag) if defined?(::CarbonRegistry)
            raw(::CarbonRegistry.script_tag) if defined?(::CarbonRegistry)
          end
          body(class: 'cds-theme-zone-g100', style: 'margin:0;background:#07111f;color:#d7e5f7;font-family:Segoe UI,Arial,sans-serif;display:grid;place-items:center;height:100vh') do
            div(style: 'max-width:360px;text-align:center;border:1px solid #263650;background:#0e1d31;padding:28px;border-radius:18px') do
              h2('Webview operacional', style: 'margin:0 0 10px;color:white')
              p(style: 'line-height:1.5') { text "A webview será usada nas etapas Google/Gmail e WhatsApp. Etapa atual: #{safe}" }
            end
          end
        end
      end

      if defined?(::Frontend)
        page_id = "installer-placeholder-#{safe.gsub(/[^a-zA-Z0-9_-]/, '_')}"
        ::Frontend.register_served_page(page_id, html: html, title: 'Glauco Webview')
        ensure_glauco_frontend_server!
        @web_browser.setUrl(::Frontend.served_page_url(page_id))
      else
        @web_browser.setText(html)
      end
    end

    def install_root_html
      html = HTML.sub('__STATE__', JSON.generate(@state).gsub('</', '<\/'))
      if defined?(::Frontend)
        ::Frontend.root_html = html
        ensure_glauco_frontend_server!
        ::Frontend.root_url
      else
        dir = File.join(Dir.tmpdir, 'glauco-licitacoes-installer')
        FileUtils.mkdir_p(dir)
        path = File.join(dir, 'installer.html')
        File.write(path, html, encoding: 'UTF-8')
        java.io.File.new(path).toURI.toString
      end
    end

    def run
      @ui_browser.setUrl(install_root_html)
      render_web_placeholder('plataforma')
      @shell.open
      until @shell.isDisposed
        @display.sleep unless @display.readAndDispatch
      end
      @display.dispose
    end
  end
end

GlaucoInstaller::App.new.run

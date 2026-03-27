# bin/basic-image-viewer.rb

# Adiciona a raiz do projeto ao $LOAD_PATH para que os 'requires' funcionem
$LOAD_PATH.unshift(File.expand_path("../../..", __dir__))

# Carrega o seu script principal
require 'examples/basic_ui_with_fs_io'

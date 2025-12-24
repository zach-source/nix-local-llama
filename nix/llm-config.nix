# Local LLM Infrastructure Configuration
# Unified configuration for llama.cpp servers and Envoy gateway routing
#
# This module defines:
# 1. Model definitions (chat, embedding, reranking)
# 2. Hardware profiles (Strix Halo, RDNA3, Vulkan)
# 3. Endpoint configurations with OpenAI-compatible aliases
# 4. Generated llama.cpp server configs
# 5. Generated Envoy gateway routing
#
# Usage:
#   let
#     llmConfig = import ./nix/llm-config.nix { inherit pkgs; };
#   in
#   llmConfig.services.chat  # Returns chat service config
#   llmConfig.envoyConfig    # Returns Envoy YAML
#   llmConfig.systemdUnits   # Returns systemd service files

{
  pkgs ? import <nixpkgs> { },
}:

let
  #############################################################################
  # HARDWARE PROFILES
  #############################################################################
  hardwareProfiles = {
    # AMD Ryzen AI Max+ 395 APU (Strix Halo) with 128GB RAM, 96GB VRAM config
    strix-halo = {
      name = "Strix Halo APU";
      gpuArch = "gfx1151";
      hsaOverride = "11.5.1";
      vramTotal = 96;
      vramAvailable = 90; # Reserve for system
      buildType = "rocm"; # UMA enabled at runtime

      # ROCm environment variables
      environment = {
        HSA_OVERRIDE_GFX_VERSION = "11.5.1";
        HIP_VISIBLE_DEVICES = "0";
        GPU_MAX_HW_QUEUES = "8";
        GGML_CUDA_ENABLE_UNIFIED_MEMORY = "1";
        ROCBLAS_USE_HIPBLASLT = "1";
        HSA_ENABLE_SDMA = "0";
        GPU_MAX_HEAP_SIZE = "99";
        GPU_MAX_ALLOC_PERCENT = "99";
        LD_LIBRARY_PATH = "/opt/rocm/lib:/usr/lib/x86_64-linux-gnu";
      };

      # Recommended flags for UMA
      defaultFlags = [
        "--flash-attn"
        "on"
        "--cache-type-k"
        "q8_0"
        "--cache-type-v"
        "q8_0"
        "--no-mmap"
        "-fit"
        "off"
        "--n-gpu-layers"
        "999"
      ];
    };

    # AMD RX 7900 XTX (discrete GPU)
    rdna3-24gb = {
      name = "RDNA3 24GB";
      gpuArch = "gfx1100";
      hsaOverride = "11.0.0";
      vramTotal = 24;
      vramAvailable = 22;
      buildType = "rocm";

      environment = {
        HSA_OVERRIDE_GFX_VERSION = "11.0.0";
        HIP_VISIBLE_DEVICES = "0";
        LD_LIBRARY_PATH = "/opt/rocm/lib";
      };

      defaultFlags = [
        "--flash-attn"
        "on"
        "--n-gpu-layers"
        "999"
      ];
    };

    # Vulkan fallback for cross-platform
    vulkan = {
      name = "Vulkan Generic";
      buildType = "vulkan";
      environment = { };
      defaultFlags = [
        "--flash-attn"
        "on"
        "--n-gpu-layers"
        "999"
      ];
    };
  };

  #############################################################################
  # MODEL LIBRARY
  #############################################################################
  modelLibrary = {
    # Chat/Completion Models
    chat = {
      qwen3-coder-30b = {
        displayName = "Qwen3-Coder-30B-A3B";
        file = "Qwen3-Coder-30B-A3B-Instruct-Q6_K.gguf";
        sizeGb = 24;
        contextMax = 262144;
        contextDefault = 262144;
        quantization = "Q6_K";
        useCase = "coding";
        parameters = "30B (3B active MoE)";
        source = "https://huggingface.co/Qwen/Qwen3-Coder-30B-A3B-Instruct-GGUF";
      };

      devstral-24b = {
        displayName = "Devstral-Small-2-24B";
        file = "Devstral-Small-2-24B-Instruct-2512-Q4_K_M.gguf";
        sizeGb = 13.3;
        contextMax = 262144;
        contextDefault = 131072;
        quantization = "Q4_K_M";
        useCase = "coding";
        parameters = "24B";
        source = "https://huggingface.co/mistralai/Devstral-Small-2-24B-GGUF";
      };

      qwen25-coder-14b = {
        displayName = "Qwen2.5-Coder-14B";
        file = "Qwen2.5-Coder-14B-Instruct-Q4_K_M.gguf";
        sizeGb = 8.0;
        contextMax = 131072;
        contextDefault = 65536;
        quantization = "Q4_K_M";
        useCase = "coding";
        parameters = "14B";
        source = "https://huggingface.co/Qwen/Qwen2.5-Coder-14B-Instruct-GGUF";
      };

      llama31-70b = {
        displayName = "Llama-3.1-70B-Instruct";
        file = "Meta-Llama-3.1-70B-Instruct-Q4_K_M.gguf";
        sizeGb = 40.0;
        contextMax = 131072;
        contextDefault = 32768;
        quantization = "Q4_K_M";
        useCase = "general";
        parameters = "70B";
        source = "https://huggingface.co/meta-llama/Meta-Llama-3.1-70B-Instruct-GGUF";
      };
    };

    # Embedding Models
    embedding = {
      qwen3-embed-8b = {
        displayName = "Qwen3-Embedding-8B";
        file = "Qwen3-Embedding-8B-Q8_0.gguf";
        sizeGb = 8.5;
        contextMax = 8192;
        contextDefault = 8192;
        quantization = "Q8_0";
        dimensions = 4096;
        source = "https://huggingface.co/Qwen/Qwen3-Embedding-8B-GGUF";
      };

      nomic-embed = {
        displayName = "Nomic-Embed-Text-v1.5";
        file = "nomic-embed-text-v1.5-Q8_0.gguf";
        sizeGb = 0.5;
        contextMax = 8192;
        contextDefault = 8192;
        quantization = "Q8_0";
        dimensions = 768;
        source = "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF";
      };
    };

    # Reranking Models
    reranking = {
      bge-reranker-v2-m3 = {
        displayName = "BGE-Reranker-v2-m3";
        file = "bge-reranker-v2-m3-Q8_0.gguf";
        sizeGb = 1.2;
        contextMax = 512;
        contextDefault = 512;
        quantization = "Q8_0";
        source = "https://huggingface.co/BAAI/bge-reranker-v2-m3-GGUF";
      };
    };
  };

  #############################################################################
  # ENDPOINT DEFINITIONS
  # Maps model types to ports and OpenAI-compatible aliases
  #############################################################################
  endpointConfig = {
    # Chat/Completions endpoint
    chat = {
      port = 8000;
      mode = "chat";
      parallelSlots = 1;

      # OpenAI-compatible model aliases
      aliases = [
        "gpt-4"
        "gpt-4-turbo"
        "gpt-4o"
        "gpt-3.5-turbo"
        "claude-3-opus"
        "claude-3-sonnet"
      ];

      # llama.cpp specific flags
      extraFlags = [
        "--parallel"
        "1"
        "--batch-size"
        "4096"
        "--ubatch-size"
        "1024"
        "--threads"
        "16"
        "--threads-batch"
        "16"
        "--cont-batching"
      ];
    };

    # Embeddings endpoint
    embedding = {
      port = 8001;
      mode = "embedding";
      parallelSlots = 4;

      aliases = [
        "text-embedding-ada-002"
        "text-embedding-3-small"
        "text-embedding-3-large"
      ];

      extraFlags = [
        "--embedding"
        "--pooling"
        "mean"
        "--parallel"
        "4"
        "--threads"
        "8"
      ];
    };

    # Reranking endpoint
    reranking = {
      port = 8002;
      mode = "reranking";
      parallelSlots = 4;

      aliases = [
        "rerank-english-v3.0"
        "rerank-multilingual-v3.0"
      ];

      extraFlags = [
        "--reranking"
        "--parallel"
        "4"
        "--threads"
        "8"
      ];
    };
  };

  #############################################################################
  # ACTIVE CONFIGURATION
  # Specify which models to use for each endpoint
  #############################################################################
  activeConfig = {
    hardware = hardwareProfiles.strix-halo;
    modelsDir = "/home/ztaylor/models";
    llamaCppDir = "/home/ztaylor/llama.cpp";
    buildDir = "build-rocm";

    # Active model selections
    services = {
      chat = {
        model = modelLibrary.chat.qwen3-coder-30b;
        endpoint = endpointConfig.chat;
        contextSize = 262144; # Override default if needed
        # Additional service-specific model aliases
        modelAliases = [
          "qwen3-coder"
          "qwen-coder"
        ];
      };

      embedding = {
        model = modelLibrary.embedding.qwen3-embed-8b;
        endpoint = endpointConfig.embedding;
        modelAliases = [ "qwen3-embed" ];
      };

      reranking = {
        model = modelLibrary.reranking.bge-reranker-v2-m3;
        endpoint = endpointConfig.reranking;
        modelAliases = [
          "bge-reranker"
          "rerank"
        ];
      };
    };

    # Envoy gateway settings
    gateway = {
      port = 4001;
      adminPort = 9901;
      timeouts = {
        chat = 600;
        embedding = 120;
        reranking = 60;
        health = 5;
        models = 10;
      };
    };
  };

  #############################################################################
  # CONFIGURATION GENERATORS
  #############################################################################

  # Generate llama.cpp server conf file content
  makeServerConf =
    name: svc:
    let
      hw = activeConfig.hardware;
      model = svc.model;
      ep = svc.endpoint;
      ctx = svc.contextSize or model.contextDefault;
    in
    ''
      # Configuration for ${model.displayName}
      # Generated by nix/llm-config.nix
      # Service: llama-server@${name}

      # Binary path
      LLAMA_BIN=${activeConfig.llamaCppDir}/${activeConfig.buildDir}/bin/llama-server

      # Model path
      MODEL_PATH=${activeConfig.modelsDir}/${model.file}

      # Server settings
      HOST=0.0.0.0
      PORT=${toString ep.port}

      # Context and GPU
      CTX_SIZE=${toString ctx}
      N_GPU_LAYERS=999

      # Mode-specific and hardware flags
      EXTRA_FLAGS=${builtins.concatStringsSep " " (hw.defaultFlags ++ ep.extraFlags)}
    '';

  # Generate systemd service file
  makeSystemdService =
    name: svc:
    let
      hw = activeConfig.hardware;
      envVars = builtins.concatStringsSep "\n" (
        builtins.attrValues (builtins.mapAttrs (k: v: "Environment=\"${k}=${v}\"") hw.environment)
      );
    in
    ''
      [Unit]
      Description=LLaMA Server (${name} - ${svc.model.displayName})
      Documentation=https://github.com/ggerganov/llama.cpp
      After=network.target
      Wants=network-online.target

      [Service]
      Type=simple
      User=%u
      Group=%u

      ${envVars}

      EnvironmentFile=/etc/llama-server/${name}.conf
      Environment="EXTRA_FLAGS="

      ExecStart=/bin/bash -c "''${LLAMA_BIN} --model ''${MODEL_PATH} --host ''${HOST} --port ''${PORT} --ctx-size ''${CTX_SIZE} --n-gpu-layers ''${N_GPU_LAYERS} ''${EXTRA_FLAGS}"

      Restart=on-failure
      RestartSec=10
      StartLimitBurst=3
      StartLimitIntervalSec=60

      LimitNOFILE=65536
      LimitMEMLOCK=infinity

      StandardOutput=journal
      StandardError=journal
      SyslogIdentifier=llama-server-${name}

      [Install]
      WantedBy=multi-user.target
    '';

  # Generate Envoy gateway configuration
  makeEnvoyConfig =
    let
      gw = activeConfig.gateway;
      svc = activeConfig.services;
    in
    ''
      # Envoy Proxy Configuration for Local LLM Infrastructure
      # Generated by nix/llm-config.nix
      #
      # Architecture:
      #   Port ${toString gw.port} (Envoy Gateway) → Routes to:
      #     /v1/embeddings  → localhost:${toString svc.embedding.endpoint.port} (${svc.embedding.model.displayName})
      #     /v1/rerank      → localhost:${toString svc.reranking.endpoint.port} (${svc.reranking.model.displayName})
      #     /v1/chat/*      → localhost:${toString svc.chat.endpoint.port} (${svc.chat.model.displayName})
      #     /v1/completions → localhost:${toString svc.chat.endpoint.port} (${svc.chat.model.displayName})
      #     /health         → localhost:${toString svc.chat.endpoint.port} (health check)
      #
      # Supported OpenAI-compatible aliases:
      #   Chat:       ${
        builtins.concatStringsSep ", " (svc.chat.endpoint.aliases ++ svc.chat.modelAliases)
      }
      #   Embeddings: ${
        builtins.concatStringsSep ", " (svc.embedding.endpoint.aliases ++ svc.embedding.modelAliases)
      }
      #   Reranking:  ${
        builtins.concatStringsSep ", " (svc.reranking.endpoint.aliases ++ svc.reranking.modelAliases)
      }

      admin:
        address:
          socket_address:
            address: 127.0.0.1
            port_value: ${toString gw.adminPort}

      static_resources:
        listeners:
        - name: llm_gateway
          address:
            socket_address:
              address: 0.0.0.0
              port_value: ${toString gw.port}
          filter_chains:
          - filters:
            - name: envoy.filters.network.http_connection_manager
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
                stat_prefix: llm_gateway
                codec_type: AUTO

                # Increase timeouts for LLM inference
                stream_idle_timeout: ${toString gw.timeouts.chat}s
                request_timeout: ${toString gw.timeouts.chat}s

                access_log:
                - name: envoy.access_loggers.stdout
                  typed_config:
                    "@type": type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog

                http_filters:
                - name: envoy.filters.http.router
                  typed_config:
                    "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router

                route_config:
                  name: llm_routes
                  virtual_hosts:
                  - name: llm_services
                    domains: ["*"]
                    routes:
                    # Embeddings → embedding backend
                    - match:
                        prefix: "/v1/embeddings"
                      route:
                        cluster: llama_embed
                        timeout: ${toString gw.timeouts.embedding}s

                    # Reranking → reranking backend
                    - match:
                        prefix: "/v1/rerank"
                      route:
                        cluster: llama_rerank
                        timeout: ${toString gw.timeouts.reranking}s

                    # Alternate rerank endpoint
                    - match:
                        prefix: "/rerank"
                      route:
                        cluster: llama_rerank
                        timeout: ${toString gw.timeouts.reranking}s

                    # Chat completions → chat backend
                    - match:
                        prefix: "/v1/chat"
                      route:
                        cluster: llama_chat
                        timeout: ${toString gw.timeouts.chat}s

                    # Legacy completions → chat backend
                    - match:
                        prefix: "/v1/completions"
                      route:
                        cluster: llama_chat
                        timeout: ${toString gw.timeouts.chat}s

                    # Models list → chat backend
                    - match:
                        prefix: "/v1/models"
                      route:
                        cluster: llama_chat
                        timeout: ${toString gw.timeouts.models}s

                    # Health check → chat backend
                    - match:
                        prefix: "/health"
                      route:
                        cluster: llama_chat
                        timeout: ${toString gw.timeouts.health}s

                    # Default catch-all → chat backend
                    - match:
                        prefix: "/"
                      route:
                        cluster: llama_chat
                        timeout: ${toString gw.timeouts.chat}s

        clusters:
        # Chat/Completions backend (${svc.chat.model.displayName})
        - name: llama_chat
          type: STATIC
          connect_timeout: 5s
          lb_policy: ROUND_ROBIN
          load_assignment:
            cluster_name: llama_chat
            endpoints:
            - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: 127.0.0.1
                      port_value: ${toString svc.chat.endpoint.port}

        # Embedding backend (${svc.embedding.model.displayName})
        - name: llama_embed
          type: STATIC
          connect_timeout: 5s
          lb_policy: ROUND_ROBIN
          load_assignment:
            cluster_name: llama_embed
            endpoints:
            - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: 127.0.0.1
                      port_value: ${toString svc.embedding.endpoint.port}

        # Reranking backend (${svc.reranking.model.displayName})
        - name: llama_rerank
          type: STATIC
          connect_timeout: 5s
          lb_policy: ROUND_ROBIN
          load_assignment:
            cluster_name: llama_rerank
            endpoints:
            - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: 127.0.0.1
                      port_value: ${toString svc.reranking.endpoint.port}
    '';

  # Generate LiteLLM config for model aliasing
  makeLiteLLMConfig =
    let
      svc = activeConfig.services;

      # Helper to create model entries
      makeModelEntries =
        serviceName: service:
        let
          ep = service.endpoint;
          allAliases = ep.aliases ++ service.modelAliases;
        in
        builtins.map (alias: ''
          - model_name: ${alias}
            litellm_params:
              model: openai/${builtins.head service.modelAliases}
              api_base: http://localhost:${toString ep.port}/v1
              api_key: "sk-local"
        '') allAliases;
    in
    ''
      # LiteLLM Proxy Configuration
      # Generated by nix/llm-config.nix
      # Provides OpenAI-compatible model aliasing

      model_list:
        # Chat/Completions models → port ${toString svc.chat.endpoint.port}
      ${builtins.concatStringsSep "\n" (makeModelEntries "chat" svc.chat)}

        # Embedding models → port ${toString svc.embedding.endpoint.port}
      ${builtins.concatStringsSep "\n" (makeModelEntries "embedding" svc.embedding)}

        # Reranking models → port ${toString svc.reranking.endpoint.port}
      ${builtins.concatStringsSep "\n" (makeModelEntries "reranking" svc.reranking)}

      litellm_settings:
        cache: true
        cache_params:
          type: "local"
          ttl: 3600
        request_timeout: 600

      general_settings:
        master_key: "sk-local-llm-master"
    '';

  # Generate documentation markdown
  makeDocumentation =
    let
      svc = activeConfig.services;
      gw = activeConfig.gateway;
    in
    ''
      # Local LLM Infrastructure Configuration

      ## Active Configuration

      | Service | Model | Port | Context |
      |---------|-------|------|---------|
      | Chat | ${svc.chat.model.displayName} | ${toString svc.chat.endpoint.port} | ${
        toString (svc.chat.contextSize or svc.chat.model.contextDefault)
      } |
      | Embedding | ${svc.embedding.model.displayName} | ${toString svc.embedding.endpoint.port} | ${toString svc.embedding.model.contextDefault} |
      | Reranking | ${svc.reranking.model.displayName} | ${toString svc.reranking.endpoint.port} | ${toString svc.reranking.model.contextDefault} |

      ## Gateway

      **Unified Endpoint:** `http://localhost:${toString gw.port}`

      | Path | Backend | Timeout |
      |------|---------|---------|
      | `/v1/chat/completions` | Chat | ${toString gw.timeouts.chat}s |
      | `/v1/embeddings` | Embedding | ${toString gw.timeouts.embedding}s |
      | `/v1/rerank` | Reranking | ${toString gw.timeouts.reranking}s |
      | `/health` | Chat | ${toString gw.timeouts.health}s |

      ## OpenAI-Compatible Aliases

      **Chat Models:**
      ${builtins.concatStringsSep ", " (svc.chat.endpoint.aliases ++ svc.chat.modelAliases)}

      **Embedding Models:**
      ${builtins.concatStringsSep ", " (svc.embedding.endpoint.aliases ++ svc.embedding.modelAliases)}

      **Reranking Models:**
      ${builtins.concatStringsSep ", " (svc.reranking.endpoint.aliases ++ svc.reranking.modelAliases)}

      ## Hardware Profile

      **${activeConfig.hardware.name}**
      - GPU Architecture: ${activeConfig.hardware.gpuArch or "N/A"}
      - VRAM Available: ${toString (activeConfig.hardware.vramAvailable or 0)}GB
      - Build Type: ${activeConfig.hardware.buildType}

      ## Quick Start

      ```bash
      # Start all services
      nix run .#envoy start

      # Test endpoints
      nix run .#envoy test

      # Chat completion
      curl http://localhost:${toString gw.port}/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{"model": "gpt-4", "messages": [{"role": "user", "content": "Hello"}]}'

      # Embeddings
      curl http://localhost:${toString gw.port}/v1/embeddings \
        -H "Content-Type: application/json" \
        -d '{"model": "text-embedding-ada-002", "input": "Hello world"}'

      # Reranking
      curl http://localhost:${toString gw.port}/v1/rerank \
        -H "Content-Type: application/json" \
        -d '{"model": "rerank-english-v3.0", "query": "What is AI?", "documents": ["AI is...", "ML is..."]}'
      ```
    '';

in
{
  # Export everything
  inherit
    hardwareProfiles
    modelLibrary
    endpointConfig
    activeConfig
    ;

  # Generated configurations
  serverConfigs = builtins.mapAttrs makeServerConf activeConfig.services;
  systemdServices = builtins.mapAttrs makeSystemdService activeConfig.services;
  envoyConfig = makeEnvoyConfig;
  litellmConfig = makeLiteLLMConfig;
  documentation = makeDocumentation;

  # Derivations for Nix store
  packages = {
    envoyConfigFile = pkgs.writeText "envoy.yaml" makeEnvoyConfig;
    litellmConfigFile = pkgs.writeText "litellm-config.yaml" makeLiteLLMConfig;
    documentationFile = pkgs.writeText "CONFIGURATION.md" makeDocumentation;

    serverConfFiles = builtins.mapAttrs (name: conf: pkgs.writeText "${name}.conf" conf) (
      builtins.mapAttrs makeServerConf activeConfig.services
    );

    systemdServiceFiles = builtins.mapAttrs (
      name: svc: pkgs.writeText "llama-server-${name}.service" svc
    ) (builtins.mapAttrs makeSystemdService activeConfig.services);
  };

  # Helper functions for customization
  lib = {
    # Create a custom configuration by overriding active config
    withConfig =
      overrides:
      let
        newConfig = activeConfig // overrides;
      in
      import ./llm-config.nix { inherit pkgs; } // { activeConfig = newConfig; };

    # Switch chat model
    withChatModel =
      modelKey:
      let
        newServices = activeConfig.services // {
          chat = activeConfig.services.chat // {
            model = modelLibrary.chat.${modelKey};
          };
        };
      in
      import ./llm-config.nix { inherit pkgs; }
      // {
        activeConfig = activeConfig // {
          services = newServices;
        };
      };

    # Switch hardware profile
    withHardware =
      profileKey:
      import ./llm-config.nix { inherit pkgs; }
      // {
        activeConfig = activeConfig // {
          hardware = hardwareProfiles.${profileKey};
        };
      };
  };
}

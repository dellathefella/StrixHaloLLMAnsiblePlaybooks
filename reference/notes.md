curl -fsSL https://pi.dev/install.sh | sh
pi install npm:@monroewilliams/pi-local


{
  "providers": {
    "local-server": {
      "baseUrl": "http://0.0.0.0:8000/v1",
      "api": "openai-completions",
      "apiKey": "local-dummy-key",
      "models": [
        { "id": "DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731",
          "name": "DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731",
          "contextWindow": 126000,
          "input":["text"]
        }
      ],
      "compat": {
        "supportsDeveloperRole": false,
        "supportsReasoningEffort": false,
      }
    }
  }
}

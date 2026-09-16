# Firmware IoTMotor

O firmware principal do ESP32-01 deve partir do sketch v6 de quatro relés e LCD que foi validado na bancada. O ESP32-S3 (`esp32-02`) mede vibração e temperatura. MQTT no broker público é destinado apenas à telemetria; o controle dos quatro canais permanece no painel HTTP da rede local. Não conecte motores ou contatores durante testes sem autenticação, intertravamento e proteções independentes.

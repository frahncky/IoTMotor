package com.example.iotmotor

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Instalação do APK baixado pelo próprio app.
///
/// O Android não permite que um app se instale sozinho: o sistema sempre mostra
/// a tela de confirmação. O que fazemos aqui é entregar o arquivo direto ao
/// instalador do sistema (PackageInstaller), sem passar pelo navegador nem
/// pela pasta de downloads.
class MainActivity : FlutterActivity() {
    private val canal = "iotmotor/atualizacao"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canal).setMethodCallHandler { chamada, resposta ->
            when (chamada.method) {
                // A permissão "instalar apps desconhecidos" é concedida uma vez, pelo usuário.
                "podeInstalar" -> resposta.success(
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()
                )
                "abrirPermissao" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            )
                        )
                    }
                    resposta.success(null)
                }
                "instalar" -> {
                    val caminho = chamada.argument<String>("caminho")
                    if (caminho.isNullOrEmpty()) {
                        resposta.error("sem_arquivo", "Caminho do APK não informado.", null)
                    } else {
                        try {
                            instalar(File(caminho))
                            resposta.success(null)
                        } catch (erro: Exception) {
                            resposta.error("falha_instalacao", erro.message, null)
                        }
                    }
                }
                else -> resposta.notImplemented()
            }
        }
    }

    private fun instalar(apk: File) {
        val instalador = packageManager.packageInstaller
        val parametros = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        val sessaoId = instalador.createSession(parametros)
        instalador.openSession(sessaoId).use { sessao ->
            sessao.openWrite("iotmotor.apk", 0, apk.length()).use { destino ->
                apk.inputStream().use { origem -> origem.copyTo(destino) }
                sessao.fsync(destino)
            }
            // O sistema abre a confirmação de instalação a partir deste aviso.
            val aviso = PendingIntent.getBroadcast(
                this,
                sessaoId,
                Intent(Intent.ACTION_PACKAGE_ADDED).setPackage(packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
            sessao.commit(aviso.intentSender)
        }
    }
}

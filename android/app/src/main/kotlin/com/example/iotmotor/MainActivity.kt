package com.example.iotmotor

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Bundle
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
///
/// O PackageInstaller não abre essa tela sozinho: ele avisa o app com
/// STATUS_PENDING_USER_ACTION e manda junto a Intent da confirmação. Quem
/// recebe esse aviso é o BroadcastReceiver abaixo — sem ele, a instalação fica
/// parada em silêncio.
class MainActivity : FlutterActivity() {
    private val canal = "iotmotor/atualizacao"
    private val acaoInstalacao = "com.example.iotmotor.INSTALACAO"
    private var metodos: MethodChannel? = null

    private val recebedor = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
                PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                    val confirmacao = confirmacaoDe(intent)
                    if (confirmacao == null) {
                        avisar("falha", "O Android não devolveu a tela de confirmação.")
                    } else {
                        confirmacao.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(confirmacao)
                    }
                }
                PackageInstaller.STATUS_SUCCESS -> avisar("instalado", null)
                else -> avisar(
                    "falha",
                    intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                        ?: "A instalação foi recusada."
                )
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun confirmacaoDe(intent: Intent): Intent? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_INTENT)
        }

    private fun avisar(estado: String, motivo: String?) {
        runOnUiThread {
            metodos?.invokeMethod("resultado", mapOf("estado" to estado, "motivo" to motivo))
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filtro = IntentFilter(acaoInstalacao)
        // O aviso é só nosso: nenhum outro app precisa alcançá-lo.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(recebedor, filtro, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(recebedor, filtro)
        }
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(recebedor)
        } catch (_: IllegalArgumentException) {
            // Já removido: nada a fazer.
        }
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val metodo = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canal)
        metodos = metodo
        metodo.setMethodCallHandler { chamada, resposta ->
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
                    val arquivo = if (caminho.isNullOrEmpty()) null else File(caminho)
                    if (arquivo == null || !arquivo.isFile || arquivo.length() <= 0L) {
                        resposta.error("sem_arquivo", "O APK baixado não foi encontrado.", null)
                    } else {
                        try {
                            instalar(arquivo)
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
        parametros.setAppPackageName(packageName)
        val sessaoId = instalador.createSession(parametros)
        instalador.openSession(sessaoId).use { sessao ->
            sessao.openWrite("iotmotor.apk", 0, apk.length()).use { destino ->
                apk.inputStream().use { origem -> origem.copyTo(destino) }
                sessao.fsync(destino)
            }
            val aviso = PendingIntent.getBroadcast(
                this,
                sessaoId,
                Intent(acaoInstalacao).setPackage(packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
            sessao.commit(aviso.intentSender)
        }
    }
}

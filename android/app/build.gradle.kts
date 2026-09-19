import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Chave de publicacao fixa (android/key.properties, fora do Git). O Android so
// aceita atualizar o app por cima se todas as versoes tiverem a mesma chave.
// Sem o arquivo, o build release usa a chave de depuracao desta maquina.
val chaveDePublicacao = Properties().apply {
    val arquivo = rootProject.file("key.properties")
    if (arquivo.exists()) arquivo.inputStream().use { load(it) }
}

android {
    namespace = "com.example.iotmotor"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.iotmotor"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (chaveDePublicacao.getProperty("storeFile") != null) {
            create("publicacao") {
                storeFile = file(chaveDePublicacao.getProperty("storeFile"))
                storePassword = chaveDePublicacao.getProperty("storePassword")
                keyAlias = chaveDePublicacao.getProperty("keyAlias")
                keyPassword = chaveDePublicacao.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                signingConfigs.findByName("publicacao") ?: signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

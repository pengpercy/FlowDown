#!/usr/bin/env python3
"""
Update missing i18n translations in Localizable.xcstrings.
This script adds missing English localizations and fixes 'new' state translations.
"""

import sys

from i18n_tools import (
    default_file_path,
    load_strings,
    print_update_summary,
    save_strings,
    update_missing_translations,
)

WELCOME_MESSAGE = (
    "**Welcome to FlowDown🐦**, a blazing fast and smooth client app for LLMs with respect of your privacy.\n\n"
    "Use Apple Intelligence or _run local models_ on supported devices. You can also _configure cloud models_ with your own provider.\n\n"
    "💡 For more information, check out [our wiki](https://flowdown.ai/docs/).\n\n"
    "---\n**What to do next?**\n\n"
    "1. Select or _add a new model_, and **create a new conversation**.\n"
    "2. Later, you can go to **Settings** to customize your experience.\n"
    "3. For any issues, feel free to [contact us](https://discord.gg/UHKMRyJcgc).\n\n"
    "✨ **Enjoy your FlowDown experience!**"
)

# Populate this map with explicit translations when introducing new keys.
# Format: {"Key": {"zh-Hans": "示例", "es": "Ejemplo"}}
NEW_STRINGS: dict[str, dict[str, str]] = {
    "Folders": {
        "de": "Ordner",
        "es": "Carpetas",
        "fr": "Dossiers",
        "ja": "フォルダ",
        "ko": "폴더",
        "zh-Hans": "文件夹",
    },
    "No Conversations": {
        "de": "Keine Unterhaltungen",
        "es": "Sin conversaciones",
        "fr": "Aucune conversation",
        "ja": "会話はありません",
        "ko": "대화 없음",
        "zh-Hans": "没有对话",
    },
    "Expanded": {
        "de": "Ausgeklappt",
        "es": "Expandido",
        "fr": "Développé",
        "ja": "展開",
        "ko": "펼침",
        "zh-Hans": "已展开",
    },
    "Collapsed": {
        "de": "Eingeklappt",
        "es": "Contraído",
        "fr": "Réduit",
        "ja": "折りたたみ",
        "ko": "접힘",
        "zh-Hans": "已折叠",
    },
    "Keep Conversations": {
        "de": "Unterhaltungen behalten",
        "es": "Conservar conversaciones",
        "fr": "Conserver les conversations",
        "ja": "会話を残す",
        "ko": "대화 유지",
        "zh-Hans": "保留对话",
    },
    "Keep the conversations in this folder as unfiled chats, or delete them together with the folder.": {
        "de": "Behalten Sie die Unterhaltungen in diesem Ordner als nicht abgelegte Chats oder löschen Sie sie zusammen mit dem Ordner.",
        "es": "Conserva las conversaciones de esta carpeta como chats sin carpeta o elimínalas junto con la carpeta.",
        "fr": "Conservez les conversations de ce dossier en dehors de tout dossier, ou supprimez-les avec le dossier.",
        "ja": "このフォルダ内の会話をフォルダ外のチャットとして残すか、フォルダと一緒に削除します。",
        "ko": "이 폴더의 대화를 폴더 밖의 채팅으로 유지하거나 폴더와 함께 삭제하세요.",
        "zh-Hans": "将此文件夹中的对话保留为未归档的对话，或将它们与文件夹一并删除。",
    },
    "New Folder": {
        "de": "Neuer Ordner",
        "es": "Nueva carpeta",
        "fr": "Nouveau dossier",
        "ja": "新規フォルダ",
        "ko": "새 폴더",
        "zh-Hans": "新建文件夹",
    },
    "Folder Name": {
        "de": "Ordnername",
        "es": "Nombre de la carpeta",
        "fr": "Nom du dossier",
        "ja": "フォルダ名",
        "ko": "폴더 이름",
        "zh-Hans": "文件夹名称",
    },
    "Create a folder for this conversation.": {
        "de": "Erstellen Sie einen Ordner fuer diese Unterhaltung.",
        "es": "Crea una carpeta para esta conversación.",
        "fr": "Créez un dossier pour cette conversation.",
        "ja": "この会話用のフォルダを作成します。",
        "ko": "이 대화를 위한 폴더를 만드세요.",
        "zh-Hans": "为此对话创建一个文件夹。",
    },
    "Create an empty folder for conversations.": {
        "de": "Erstellen Sie einen leeren Ordner fuer Unterhaltungen.",
        "es": "Crea una carpeta vacía para conversaciones.",
        "fr": "Créez un dossier vide pour les conversations.",
        "ja": "会話用の空のフォルダを作成します。",
        "ko": "대화를 위한 빈 폴더를 만드세요.",
        "zh-Hans": "创建一个用于存放对话的空文件夹。",
    },
    "Rename Folder": {
        "de": "Ordner umbenennen",
        "es": "Renombrar carpeta",
        "fr": "Renommer le dossier",
        "ja": "フォルダ名を変更",
        "ko": "폴더 이름 변경",
        "zh-Hans": "重命名文件夹",
    },
    "Delete Folder": {
        "de": "Ordner löschen",
        "es": "Eliminar carpeta",
        "fr": "Supprimer le dossier",
        "ja": "フォルダを削除",
        "ko": "폴더 삭제",
        "zh-Hans": "删除文件夹",
    },
    "Move to Folder": {
        "de": "In Ordner verschieben",
        "es": "Mover a la carpeta",
        "fr": "Déplacer vers le dossier",
        "ja": "フォルダに移動",
        "ko": "폴더로 이동",
        "zh-Hans": "移动到文件夹",
    },
    "Remove from Folder": {
        "de": "Aus Ordner entfernen",
        "es": "Quitar de la carpeta",
        "fr": "Retirer du dossier",
        "ja": "フォルダから移動",
        "ko": "폴더에서 제거",
        "zh-Hans": "移出文件夹",
    },
    "Set a new name for the folder.": {
        "de": "Geben Sie einen neuen Namen fuer den Ordner ein.",
        "es": "Establece un nuevo nombre para la carpeta.",
        "fr": "Définissez un nouveau nom pour le dossier.",
        "ja": "フォルダの新しい名前を設定します。",
        "ko": "폴더의 새 이름을 설정하세요.",
        "zh-Hans": "为文件夹设置一个新名称。",
    },
    "Collapsible Code Blocks": {
        "de": "Einklappbare Codeblöcke",
        "es": "Bloques de código plegables",
        "fr": "Blocs de code repliables",
        "ja": "コードブロックの折りたたみ",
        "ko": "코드 블록 접기",
        "zh-Hans": "代码块可折叠",
    },
    "Collapse long code blocks into a short, scrollable preview that expands on demand. Turn this off to always show code blocks in full.": {
        "de": "Lange Codeblöcke werden zu einer kurzen, scrollbaren Vorschau eingeklappt, die sich bei Bedarf erweitern lässt. Deaktiviere diese Option, um Codeblöcke immer vollständig anzuzeigen.",
        "es": "Contrae los bloques de código largos en una vista previa corta y desplazable que se expande bajo demanda. Desactiva esta opción para mostrar siempre los bloques de código completos.",
        "fr": "Réduit les longs blocs de code en un court aperçu défilable qui se déploie à la demande. Désactivez cette option pour toujours afficher les blocs de code en entier.",
        "ja": "長いコードブロックをスクロール可能な短いプレビューに折りたたみ、必要に応じて展開します。オフにすると、コードブロックが常に全体表示されます。",
        "ko": "긴 코드 블록을 스크롤 가능한 짧은 미리보기로 접고 필요할 때 펼칩니다. 끄면 코드 블록이 항상 전체로 표시됩니다.",
        "zh-Hans": "将较长的代码块折叠为可滚动的简短预览，可按需展开。关闭后代码块将始终完整显示。",
    },
    "Authorization (Optional)": {
        "de": "Autorisierung (optional)",
        "es": "Autorización (opcional)",
        "fr": "Autorisation (facultatif)",
        "ja": "Authorization（任意）",
        "ko": "Authorization(선택 사항)",
        "zh-Hans": "Authorization（可选）",
    },
    "Bearer token": {
        "de": "Bearer-Token",
        "es": "Token Bearer",
        "fr": "Jeton Bearer",
        "ja": "Bearer トークン",
        "ko": "Bearer 토큰",
        "zh-Hans": "Bearer 令牌",
    },
    "Delete All": {
        "de": "Alle löschen",
        "es": "Eliminar todo",
        "fr": "Tout supprimer",
        "ja": "すべて削除",
        "ko": "모두 삭제",
        "zh-Hans": "全部删除",
    },
    "Edit Authorization (Optional)": {
        "de": "Autorisierung bearbeiten (optional)",
        "es": "Editar autorización (opcional)",
        "fr": "Modifier l’autorisation (facultatif)",
        "ja": "Authorization を編集（任意）",
        "ko": "Authorization 편집(선택 사항)",
        "zh-Hans": "编辑 Authorization（可选）",
    },
    "This token is sent as a Bearer credential in the Authorization header.": {
        "de": "Dieses Token wird als Bearer-Zugangsdaten im Authorization-Header gesendet.",
        "es": "Este token se envía como credencial Bearer en el encabezado Authorization.",
        "fr": "Ce jeton est envoyé comme identifiant Bearer dans l’en-tête Authorization.",
        "ja": "このトークンは Authorization ヘッダーの Bearer 認証情報として送信されます。",
        "ko": "이 토큰은 Authorization 헤더의 Bearer 인증 정보로 전송됩니다.",
        "zh-Hans": "此令牌会作为 Bearer 凭据通过 Authorization 标头发送。",
    },
    "This token is sent as a Bearer credential in the Authorization header. Leave it blank if the endpoint does not require authentication.": {
        "de": "Dieses Token wird als Bearer-Zugangsdaten im Authorization-Header gesendet. Lassen Sie es leer, wenn der Endpunkt keine Authentifizierung erfordert.",
        "es": "Este token se envía como credencial Bearer en el encabezado Authorization. Déjalo en blanco si el endpoint no requiere autenticación.",
        "fr": "Ce jeton est envoyé comme identifiant Bearer dans l’en-tête Authorization. Laissez-le vide si le point de terminaison ne nécessite pas d’authentification.",
        "ja": "このトークンは Authorization ヘッダーの Bearer 認証情報として送信されます。エンドポイントで認証が不要な場合は空欄にしてください。",
        "ko": "이 토큰은 Authorization 헤더의 Bearer 인증 정보로 전송됩니다. 엔드포인트에 인증이 필요하지 않으면 비워 두세요.",
        "zh-Hans": "此令牌会作为 Bearer 凭据通过 Authorization 标头发送。如果端点不需要身份验证，请留空。",
    },
    "Would you like to apply the new Authorization token to all models with the same inference endpoint and current token?": {
        "de": "Möchten Sie das neue Autorisierungs-Token auf alle Modelle mit demselben Inferenzendpunkt und dem aktuellen Token anwenden?",
        "es": "¿Quieres aplicar el nuevo token de autorización a todos los modelos con el mismo endpoint de inferencia y el token actual?",
        "fr": "Voulez-vous appliquer le nouveau jeton d’autorisation à tous les modèles ayant le même point de terminaison d’inférence et le jeton actuel ?",
        "ja": "同じ推論エンドポイントと現在のトークンを使用するすべてのモデルに、新しい Authorization トークンを適用しますか？",
        "ko": "동일한 추론 엔드포인트와 현재 토큰을 사용하는 모든 모델에 새 Authorization 토큰을 적용할까요?",
        "zh-Hans": "是否将新的 Authorization 令牌应用到推理端点和当前令牌均相同的所有模型？",
    },
    WELCOME_MESSAGE: {
        "de": (
            "**Willkommen bei FlowDown🐦**, einer blitzschnellen und flüssigen Client-App für LLMs, die deine Privatsphäre respektiert.\n\n"
            "Verwende Apple Intelligence oder führe auf unterstützten Geräten _lokale Modelle_ aus. Du kannst außerdem _Cloud-Modelle_ mit deinem eigenen Anbieter konfigurieren.\n\n"
            "💡 Weitere Infos findest du in [unserem Wiki](https://flowdown.ai/docs/).\n\n"
            "---\n**Was als Nächstes?**\n\n"
            "1. Wähle oder _füge ein neues Modell hinzu_ und **erstelle eine neue Unterhaltung**.\n"
            "2. Später kannst du in den **Einstellungen** dein Erlebnis anpassen.\n"
            "3. Bei Fragen: [kontaktiere uns](https://discord.gg/UHKMRyJcgc).\n\n"
            "✨ **Viel Spaß mit FlowDown!**"
        ),
        "es": (
            "**Bienvenido a FlowDown🐦**, una app de cliente para LLMs rápida y fluida que respeta tu privacidad.\n\n"
            "Usa Apple Intelligence o _ejecuta modelos locales_ en dispositivos compatibles. También puedes _configurar modelos en la nube_ con tu propio proveedor.\n\n"
            "💡 Para más información, consulta [nuestra wiki](https://flowdown.ai/docs/).\n\n"
            "---\n**¿Qué hacer a continuación?**\n\n"
            "1. Selecciona o _añade un modelo nuevo_ y **crea una conversación nueva**.\n"
            "2. Luego puedes ir a **Ajustes** para personalizar tu experiencia.\n"
            "3. Si tienes alguna duda, [contáctanos](https://discord.gg/UHKMRyJcgc).\n\n"
            "✨ **¡Disfruta la experiencia FlowDown!**"
        ),
        "fr": (
            "**Bienvenue sur FlowDown🐦**, une application cliente ultra-rapide et fluide pour les LLMs, respectueuse de votre vie privée.\n\n"
            "Utilisez Apple Intelligence ou _exécutez des modèles locaux_ sur les appareils compatibles. Vous pouvez aussi _configurer des modèles cloud_ avec votre propre fournisseur.\n\n"
            "💡 Pour en savoir plus, consultez [notre wiki](https://flowdown.ai/docs/).\n\n"
            "---\n**Que faire ensuite ?**\n\n"
            "1. Sélectionnez ou _ajoutez un nouveau modèle_, puis **créez une nouvelle conversation**.\n"
            "2. Plus tard, vous pourrez aller dans **Réglages** pour personnaliser votre expérience.\n"
            "3. Pour tout problème, [contactez-nous](https://discord.gg/UHKMRyJcgc).\n\n"
            "✨ **Profitez de votre expérience FlowDown !**"
        ),
        "ja": (
            "**FlowDown🐦 へようこそ**。プライバシーを重視した高速で滑らかな LLM クライアントです。\n\n"
            "Apple Intelligence を使用するか、対応デバイス上で _ローカルモデルを実行_ できます。また、独自のプロバイダで _クラウドモデルを設定_ することもできます。\n\n"
            "💡 詳細は[ウィキ](https://flowdown.ai/docs/)をご覧ください。\n\n"
            "---\n**次にやること**\n\n"
            "1. _新しいモデルを選ぶ/追加_ して **新しい会話を作成**。\n"
            "2. あとで **設定** から体験をカスタマイズ。\n"
            "3. 問題があれば[お問い合わせ](https://discord.gg/UHKMRyJcgc)。\n\n"
            "✨ **FlowDown をお楽しみください！**"
        ),
        "ko": (
            "**FlowDown🐦에 오신 것을 환영합니다.** 빠르고 부드러운 LLM 클라이언트로 개인정보를 존중합니다.\n\n"
            "Apple Intelligence를 사용하거나 지원되는 기기에서 _로컬 모델을 실행_하세요. 자체 제공업체로 _클라우드 모델을 설정_할 수도 있습니다.\n\n"
            "💡 더 자세한 정보는 [위키](https://flowdown.ai/docs/)를 확인하세요.\n\n"
            "---\n**다음에 무엇을 할까요?**\n\n"
            "1. 모델을 선택하거나 _새 모델을 추가_하고 **새 대화를 만드세요.**\n"
            "2. 나중에 **설정**에서 경험을 맞춤화할 수 있습니다.\n"
            "3. 문제가 있으면 언제든지 [문의하기](https://discord.gg/UHKMRyJcgc)로 연락하세요.\n\n"
            "✨ **FlowDown을 마음껏 즐겨보세요!**"
        ),
        "zh-Hans": (
            "**欢迎使用 FlowDown 🐦**，一款注重隐私、极速流畅且轻量高效的 LLM 客户端。\n\n"
            "你可以使用 Apple Intelligence，或在支持的设备上 _运行本地模型_。也可以使用自己的服务提供商 _配置云端模型_。\n\n"
            "💡 更多信息，请查阅[用户手册](https://flowdown.ai/docs/)。\n\n"
            "---\n**接下来可以做些什么？**\n\n"
            "1.  _选择或添加新模型_，然后 **开始一个新对话**。\n"
            "2.  之后，你可以前往 **设置** 来自定义你的使用体验。\n"
            "3.  若有任何疑问反馈或建议，欢迎[联系我们](https://discord.gg/UHKMRyJcgc)。\n\n"
            "✨ **祝你使用愉快！**"
        ),
    },
    "API Key": {
        "de": "API-Schlüssel",
        "es": "Clave de API",
        "fr": "Clé API",
        "ja": "APIキー",
        "ko": "API 키",
        "zh-Hans": "API 密钥",
    },
    "API Type": {
        "de": "API-Typ",
        "es": "Tipo de API",
        "fr": "Type d'API",
        "ja": "APIタイプ",
        "ko": "API 유형",
        "zh-Hans": "API 类型",
    },
    "Add Model Manually": {
        "de": "Modell manuell hinzufügen",
        "es": "Añadir modelo manualmente",
        "fr": "Ajouter un modèle manuellement",
        "ja": "モデルを手動で追加",
        "ko": "수동으로 모델 추가",
        "zh-Hans": "手动添加模型",
    },
    "Add Provider": {
        "de": "Anbieter hinzufügen",
        "es": "Añadir proveedor",
        "fr": "Ajouter un fournisseur",
        "ja": "プロバイダを追加",
        "ko": "제공자 추가",
        "zh-Hans": "添加服务商",
    },
    "Advanced": {
        "de": "Erweitert",
        "es": "Avanzado",
        "fr": "Avancé",
        "ja": "詳細設定",
        "ko": "고급",
        "zh-Hans": "高级",
    },
    "Anthropic Messages": {
        "de": "Anthropic Messages",
        "es": "Anthropic Messages",
        "fr": "Anthropic Messages",
        "ja": "Anthropic Messages",
        "ko": "Anthropic Messages",
        "zh-Hans": "Anthropic Messages",
    },
    "Base URL": {
        "de": "Basis-URL",
        "es": "URL base",
        "fr": "URL de base",
        "ja": "ベースURL",
        "ko": "기본 URL",
        "zh-Hans": "基础 URL",
    },
    "Check Connection Settings": {
        "de": "Verbindungseinstellungen prüfen",
        "es": "Revisa la configuración de conexión",
        "fr": "Vérifiez les paramètres de connexion",
        "ja": "接続設定を確認してください",
        "ko": "연결 설정을 확인하세요",
        "zh-Hans": "请检查连接设置",
    },
    "Check at least one model. To remove this provider, use Delete Provider.": {
        "de": "Wählen Sie mindestens ein Modell aus. Um diesen Anbieter zu entfernen, verwenden Sie „Anbieter löschen“.",
        "es": "Marca al menos un modelo. Para eliminar este proveedor, usa Eliminar proveedor.",
        "fr": "Cochez au moins un modèle. Pour retirer ce fournisseur, utilisez Supprimer le fournisseur.",
        "ja": "少なくとも1つのモデルを選択してください。このプロバイダを削除するには「プロバイダを削除」を使用してください。",
        "ko": "모델을 하나 이상 선택하세요. 이 제공자를 제거하려면 제공자 삭제를 사용하세요.",
        "zh-Hans": "请至少勾选一个模型。如需移除此服务商，请使用“删除服务商”。",
    },
    "Checked models appear in the model picker. Per-model options such as capabilities and context length can be changed later in each model's settings.": {
        "de": "Ausgewählte Modelle erscheinen in der Modellauswahl. Optionen wie Fähigkeiten und Kontextlänge können später in den Einstellungen des jeweiligen Modells geändert werden.",
        "es": "Los modelos marcados aparecen en el selector de modelos. Las opciones de cada modelo, como capacidades y longitud de contexto, se pueden cambiar después en su configuración.",
        "fr": "Les modèles cochés apparaissent dans le sélecteur de modèles. Les options propres à chaque modèle, comme les capacités et la longueur de contexte, peuvent être modifiées ensuite dans ses réglages.",
        "ja": "チェックしたモデルはモデル選択に表示されます。機能やコンテキスト長などのモデルごとの設定は、後で各モデルの設定で変更できます。",
        "ko": "선택한 모델은 모델 선택기에 표시됩니다. 기능 및 컨텍스트 길이 같은 모델별 옵션은 나중에 각 모델 설정에서 변경할 수 있습니다.",
        "zh-Hans": "勾选的模型会出现在模型选择器中。能力和上下文长度等单个模型的选项，可稍后在各模型的设置中修改。",
    },
    "Connected, %lld models available": {
        "de": "Verbunden, %lld Modelle verfügbar",
        "es": "Conectado, %lld modelos disponibles",
        "fr": "Connecté, %lld modèles disponibles",
        "ja": "接続しました。%lld 個のモデルが利用可能です",
        "ko": "연결됨, 사용 가능한 모델 %lld개",
        "zh-Hans": "已连接，共有 %lld 个可用模型",
    },
    "Connection settings shared by all models from this provider.": {
        "de": "Verbindungseinstellungen, die alle Modelle dieses Anbieters teilen.",
        "es": "Configuración de conexión compartida por todos los modelos de este proveedor.",
        "fr": "Paramètres de connexion partagés par tous les modèles de ce fournisseur.",
        "ja": "このプロバイダのすべてのモデルで共有される接続設定です。",
        "ko": "이 제공자의 모든 모델이 공유하는 연결 설정입니다.",
        "zh-Hans": "此服务商所有模型共享的连接设置。",
    },
    "Custom": {
        "de": "Benutzerdefiniert",
        "es": "Personalizado",
        "fr": "Personnalisé",
        "ja": "カスタム",
        "ko": "사용자 지정",
        "zh-Hans": "自定义",
    },
    "Custom Headers": {
        "de": "Benutzerdefinierte Header",
        "es": "Encabezados personalizados",
        "fr": "En-têtes personnalisés",
        "ja": "カスタムヘッダー",
        "ko": "사용자 지정 헤더",
        "zh-Hans": "自定义请求头",
    },
    "Custom Provider": {
        "de": "Benutzerdefinierter Anbieter",
        "es": "Proveedor personalizado",
        "fr": "Fournisseur personnalisé",
        "ja": "カスタムプロバイダ",
        "ko": "사용자 지정 제공자",
        "zh-Hans": "自定义服务商",
    },
    "Custom headers are sent with every request to this provider and can override the default authorization.": {
        "de": "Benutzerdefinierte Header werden mit jeder Anfrage an diesen Anbieter gesendet und können die Standard-Autorisierung überschreiben.",
        "es": "Los encabezados personalizados se envían con cada solicitud a este proveedor y pueden reemplazar la autorización predeterminada.",
        "fr": "Les en-têtes personnalisés sont envoyés avec chaque requête à ce fournisseur et peuvent remplacer l'autorisation par défaut.",
        "ja": "カスタムヘッダーはこのプロバイダへのすべてのリクエストに付加され、既定の認証を上書きできます。",
        "ko": "사용자 지정 헤더는 이 제공자에 대한 모든 요청에 포함되며 기본 인증을 덮어쓸 수 있습니다.",
        "zh-Hans": "自定义请求头会随发往此服务商的每个请求发送，并可覆盖默认的认证信息。",
    },
    "Delete Provider": {
        "de": "Anbieter löschen",
        "es": "Eliminar proveedor",
        "fr": "Supprimer le fournisseur",
        "ja": "プロバイダを削除",
        "ko": "제공자 삭제",
        "zh-Hans": "删除服务商",
    },
    "Delete this provider and its %lld models? Conversations keep their messages.": {
        "de": "Diesen Anbieter und seine %lld Modelle löschen? Unterhaltungen behalten ihre Nachrichten.",
        "es": "¿Eliminar este proveedor y sus %lld modelos? Las conversaciones conservan sus mensajes.",
        "fr": "Supprimer ce fournisseur et ses %lld modèles ? Les conversations conservent leurs messages.",
        "ja": "このプロバイダと %lld 個のモデルを削除しますか？会話のメッセージは保持されます。",
        "ko": "이 제공자와 모델 %lld개를 삭제하시겠습니까? 대화 메시지는 유지됩니다.",
        "zh-Hans": "要删除此服务商及其 %lld 个模型吗？对话中的消息会保留。",
    },
    "Deselect All": {
        "de": "Alle abwählen",
        "es": "Desmarcar todo",
        "fr": "Tout désélectionner",
        "ja": "すべて選択解除",
        "ko": "모두 선택 해제",
        "zh-Hans": "取消全选",
    },
    "Edit Provider": {
        "de": "Anbieter bearbeiten",
        "es": "Editar proveedor",
        "fr": "Modifier le fournisseur",
        "ja": "プロバイダを編集",
        "ko": "제공자 편집",
        "zh-Hans": "编辑服务商",
    },
    "Enter the base URL of the provider.": {
        "de": "Geben Sie die Basis-URL des Anbieters ein.",
        "es": "Introduce la URL base del proveedor.",
        "fr": "Saisissez l'URL de base du fournisseur.",
        "ja": "プロバイダのベースURLを入力してください。",
        "ko": "제공자의 기본 URL을 입력하세요.",
        "zh-Hans": "请输入服务商的基础 URL。",
    },
    "Enter the model identifier exactly as the provider documents it.": {
        "de": "Geben Sie die Modellkennung genau so ein, wie der Anbieter sie dokumentiert.",
        "es": "Introduce el identificador del modelo exactamente como lo documenta el proveedor.",
        "fr": "Saisissez l'identifiant du modèle exactement comme le documente le fournisseur.",
        "ja": "プロバイダのドキュメントに記載されたとおりにモデル識別子を入力してください。",
        "ko": "제공자 문서에 나와 있는 그대로 모델 식별자를 입력하세요.",
        "zh-Hans": "请按服务商文档中的写法准确输入模型标识符。",
    },
    "Fetch Model List": {
        "de": "Modellliste abrufen",
        "es": "Obtener lista de modelos",
        "fr": "Récupérer la liste des modèles",
        "ja": "モデル一覧を取得",
        "ko": "모델 목록 가져오기",
        "zh-Hans": "获取模型列表",
    },
    "Fetch the model list or add a model manually, then check the models you want to use.": {
        "de": "Rufen Sie die Modellliste ab oder fügen Sie ein Modell manuell hinzu und wählen Sie dann die gewünschten Modelle aus.",
        "es": "Obtén la lista de modelos o añade uno manualmente y luego marca los modelos que quieras usar.",
        "fr": "Récupérez la liste des modèles ou ajoutez-en un manuellement, puis cochez ceux que vous voulez utiliser.",
        "ja": "モデル一覧を取得するか手動でモデルを追加し、使用するモデルにチェックを入れてください。",
        "ko": "모델 목록을 가져오거나 수동으로 모델을 추가한 다음 사용할 모델을 선택하세요.",
        "zh-Hans": "请获取模型列表或手动添加模型，然后勾选要使用的模型。",
    },
    "Filter models": {
        "de": "Modelle filtern",
        "es": "Filtrar modelos",
        "fr": "Filtrer les modèles",
        "ja": "モデルを絞り込む",
        "ko": "모델 필터",
        "zh-Hans": "筛选模型",
    },
    "Get an API Key": {
        "de": "API-Schlüssel erhalten",
        "es": "Obtener una clave de API",
        "fr": "Obtenir une clé API",
        "ja": "APIキーを取得",
        "ko": "API 키 받기",
        "zh-Hans": "获取 API 密钥",
    },
    "Most compatible. Used by OpenAI and almost every third-party or local server.": {
        "de": "Am kompatibelsten. Wird von OpenAI und fast allen Drittanbieter- oder lokalen Servern verwendet.",
        "es": "La más compatible. La usan OpenAI y casi todos los servidores de terceros o locales.",
        "fr": "La plus compatible. Utilisée par OpenAI et presque tous les serveurs tiers ou locaux.",
        "ja": "最も互換性が高い形式です。OpenAI とほぼすべてのサードパーティ製・ローカルサーバーで使われています。",
        "ko": "가장 호환성이 높습니다. OpenAI와 거의 모든 타사 또는 로컬 서버에서 사용됩니다.",
        "zh-Hans": "兼容性最好。OpenAI 及几乎所有第三方或本地服务都支持。",
    },
    "Native Claude API, also offered by some compatible providers.": {
        "de": "Native Claude-API, die auch von einigen kompatiblen Anbietern angeboten wird.",
        "es": "API nativa de Claude, también ofrecida por algunos proveedores compatibles.",
        "fr": "API native de Claude, également proposée par certains fournisseurs compatibles.",
        "ja": "Claude のネイティブ API です。一部の互換プロバイダでも提供されています。",
        "ko": "Claude의 기본 API로, 일부 호환 제공자도 제공합니다.",
        "zh-Hans": "Claude 原生 API，部分兼容服务商也提供此接口。",
    },
    "No API key is set. Most cloud providers reject requests without one.": {
        "de": "Es ist kein API-Schlüssel festgelegt. Die meisten Cloud-Anbieter lehnen Anfragen ohne Schlüssel ab.",
        "es": "No hay ninguna clave de API. La mayoría de los proveedores en la nube rechazan solicitudes sin ella.",
        "fr": "Aucune clé API n'est définie. La plupart des fournisseurs cloud refusent les requêtes sans clé.",
        "ja": "APIキーが設定されていません。ほとんどのクラウドプロバイダはキーのないリクエストを拒否します。",
        "ko": "API 키가 설정되지 않았습니다. 대부분의 클라우드 제공자는 키 없는 요청을 거부합니다.",
        "zh-Hans": "尚未设置 API 密钥。大多数云服务商会拒绝没有密钥的请求。",
    },
    "No Models Selected": {
        "de": "Keine Modelle ausgewählt",
        "es": "No hay modelos seleccionados",
        "fr": "Aucun modèle sélectionné",
        "ja": "モデルが選択されていません",
        "ko": "선택된 모델 없음",
        "zh-Hans": "未选择模型",
    },
    "OpenAI Chat Completions": {
        "de": "OpenAI Chat Completions",
        "es": "OpenAI Chat Completions",
        "fr": "OpenAI Chat Completions",
        "ja": "OpenAI Chat Completions",
        "ko": "OpenAI Chat Completions",
        "zh-Hans": "OpenAI Chat Completions",
    },
    "OpenAI Responses": {
        "de": "OpenAI Responses",
        "es": "OpenAI Responses",
        "fr": "OpenAI Responses",
        "ja": "OpenAI Responses",
        "ko": "OpenAI Responses",
        "zh-Hans": "OpenAI Responses",
    },
    "OpenAI's newer API with better support for reasoning models.": {
        "de": "Die neuere API von OpenAI mit besserer Unterstützung für Reasoning-Modelle.",
        "es": "La API más reciente de OpenAI, con mejor soporte para modelos de razonamiento.",
        "fr": "La nouvelle API d'OpenAI, mieux adaptée aux modèles de raisonnement.",
        "ja": "推論モデルへの対応が強化された OpenAI の新しい API です。",
        "ko": "추론 모델을 더 잘 지원하는 OpenAI의 최신 API입니다.",
        "zh-Hans": "OpenAI 的新版 API，对推理模型的支持更好。",
    },
    "Paste your API key": {
        "de": "API-Schlüssel einfügen",
        "es": "Pega tu clave de API",
        "fr": "Collez votre clé API",
        "ja": "APIキーを貼り付け",
        "ko": "API 키를 붙여넣으세요",
        "zh-Hans": "粘贴你的 API 密钥",
    },
    "Pick a known provider to fill in its address, or choose Custom for any compatible server.": {
        "de": "Wählen Sie einen bekannten Anbieter, um dessen Adresse einzutragen, oder „Benutzerdefiniert“ für jeden kompatiblen Server.",
        "es": "Elige un proveedor conocido para rellenar su dirección, o Personalizado para cualquier servidor compatible.",
        "fr": "Choisissez un fournisseur connu pour renseigner son adresse, ou Personnalisé pour tout serveur compatible.",
        "ja": "既知のプロバイダを選ぶとアドレスが入力されます。互換サーバーの場合は「カスタム」を選択してください。",
        "ko": "알려진 제공자를 선택하면 주소가 채워집니다. 호환 서버는 사용자 지정을 선택하세요.",
        "zh-Hans": "选择常用服务商可自动填写地址，其他兼容服务请选择“自定义”。",
    },
    "Preset": {
        "de": "Vorlage",
        "es": "Plantilla",
        "fr": "Modèle prédéfini",
        "ja": "プリセット",
        "ko": "프리셋",
        "zh-Hans": "预设",
    },
    "Provider": {
        "de": "Anbieter",
        "es": "Proveedor",
        "fr": "Fournisseur",
        "ja": "プロバイダ",
        "ko": "제공자",
        "zh-Hans": "服务商",
    },
    "Providers": {
        "de": "Anbieter",
        "es": "Proveedores",
        "fr": "Fournisseurs",
        "ja": "プロバイダ",
        "ko": "제공자",
        "zh-Hans": "服务商",
    },
    "Remove Unchecked Models": {
        "de": "Nicht ausgewählte Modelle entfernen",
        "es": "Eliminar modelos desmarcados",
        "fr": "Retirer les modèles décochés",
        "ja": "チェックを外したモデルを削除",
        "ko": "선택 해제된 모델 제거",
        "zh-Hans": "移除未勾选的模型",
    },
    "Requests are sent to %@": {
        "de": "Anfragen werden an %@ gesendet",
        "es": "Las solicitudes se envían a %@",
        "fr": "Les requêtes sont envoyées à %@",
        "ja": "リクエストの送信先：%@",
        "ko": "요청 전송 위치: %@",
        "zh-Hans": "请求将发送至 %@",
    },
    "Save": {
        "de": "Speichern",
        "es": "Guardar",
        "fr": "Enregistrer",
        "ja": "保存",
        "ko": "저장",
        "zh-Hans": "保存",
    },
    "Select All": {
        "de": "Alle auswählen",
        "es": "Seleccionar todo",
        "fr": "Tout sélectionner",
        "ja": "すべて選択",
        "ko": "모두 선택",
        "zh-Hans": "全选",
    },
    "Show API Key": {
        "de": "API-Schlüssel anzeigen",
        "es": "Mostrar clave de API",
        "fr": "Afficher la clé API",
        "ja": "APIキーを表示",
        "ko": "API 키 보기",
        "zh-Hans": "显示 API 密钥",
    },
    "Test Connection": {
        "de": "Verbindung testen",
        "es": "Probar conexión",
        "fr": "Tester la connexion",
        "ja": "接続をテスト",
        "ko": "연결 테스트",
        "zh-Hans": "测试连接",
    },
    "The API contract this model uses for requests.": {
        "de": "Der API-Vertrag, den dieses Modell für Anfragen verwendet.",
        "es": "El contrato de API que usa este modelo para las solicitudes.",
        "fr": "Le contrat d'API utilisé par ce modèle pour ses requêtes.",
        "ja": "このモデルがリクエストに使用する API の形式です。",
        "ko": "이 모델이 요청에 사용하는 API 규격입니다.",
        "zh-Hans": "此模型发送请求时使用的 API 接口类型。",
    },
    "The base URL is not valid.": {
        "de": "Die Basis-URL ist ungültig.",
        "es": "La URL base no es válida.",
        "fr": "L'URL de base n'est pas valide.",
        "ja": "ベースURLが無効です。",
        "ko": "기본 URL이 올바르지 않습니다.",
        "zh-Hans": "基础 URL 无效。",
    },
    "The base URL must be a full address starting with http:// or https://.": {
        "de": "Die Basis-URL muss eine vollständige Adresse sein, die mit http:// oder https:// beginnt.",
        "es": "La URL base debe ser una dirección completa que empiece por http:// o https://.",
        "fr": "L'URL de base doit être une adresse complète commençant par http:// ou https://.",
        "ja": "ベースURLは http:// または https:// で始まる完全なアドレスである必要があります。",
        "ko": "기본 URL은 http:// 또는 https://로 시작하는 전체 주소여야 합니다.",
        "zh-Hans": "基础 URL 必须是以 http:// 或 https:// 开头的完整地址。",
    },
    "The endpoint must be the full request URL, such as /v1/chat/completions, /v1/responses or /v1/messages. To change the endpoint or API key of every model from this provider at once, edit the provider.": {
        "de": "Der Endpunkt muss die vollständige Anfrage-URL sein, z. B. /v1/chat/completions, /v1/responses oder /v1/messages. Um Endpunkt oder API-Schlüssel aller Modelle dieses Anbieters auf einmal zu ändern, bearbeiten Sie den Anbieter.",
        "es": "El endpoint debe ser la URL completa de la solicitud, como /v1/chat/completions, /v1/responses o /v1/messages. Para cambiar el endpoint o la clave de API de todos los modelos de este proveedor a la vez, edita el proveedor.",
        "fr": "Le point de terminaison doit être l'URL complète de la requête, par exemple /v1/chat/completions, /v1/responses ou /v1/messages. Pour modifier le point de terminaison ou la clé API de tous les modèles de ce fournisseur à la fois, modifiez le fournisseur.",
        "ja": "エンドポイントには /v1/chat/completions、/v1/responses、/v1/messages などの完全なリクエストURLを指定してください。このプロバイダのすべてのモデルのエンドポイントやAPIキーをまとめて変更するには、プロバイダを編集してください。",
        "ko": "엔드포인트는 /v1/chat/completions, /v1/responses 또는 /v1/messages와 같은 전체 요청 URL이어야 합니다. 이 제공자의 모든 모델의 엔드포인트나 API 키를 한 번에 변경하려면 제공자를 편집하세요.",
        "zh-Hans": "端点必须是完整的请求 URL，例如 /v1/chat/completions、/v1/responses 或 /v1/messages。如需一次性修改此服务商所有模型的端点或 API 密钥，请编辑服务商。",
    },
    "The inference endpoint is not a valid URL.": {
        "de": "Der Inferenz-Endpunkt ist keine gültige URL.",
        "es": "El endpoint de inferencia no es una URL válida.",
        "fr": "Le point de terminaison d'inférence n'est pas une URL valide.",
        "ja": "推論エンドポイントが有効なURLではありません。",
        "ko": "추론 엔드포인트가 올바른 URL이 아닙니다.",
        "zh-Hans": "推理端点不是有效的 URL。",
    },
    "The server responded with status %lld.": {
        "de": "Der Server antwortete mit Status %lld.",
        "es": "El servidor respondió con el estado %lld.",
        "fr": "Le serveur a répondu avec le statut %lld.",
        "ja": "サーバーがステータス %lld を返しました。",
        "ko": "서버가 상태 %lld(으)로 응답했습니다.",
        "zh-Hans": "服务器返回状态码 %lld。",
    },
    "The server responded with status %lld: %@": {
        "de": "Der Server antwortete mit Status %lld: %@",
        "es": "El servidor respondió con el estado %lld: %@",
        "fr": "Le serveur a répondu avec le statut %lld : %@",
        "ja": "サーバーがステータス %lld を返しました：%@",
        "ko": "서버가 상태 %lld(으)로 응답했습니다: %@",
        "zh-Hans": "服务器返回状态码 %lld：%@",
    },
    "The server response does not contain a model list.": {
        "de": "Die Serverantwort enthält keine Modellliste.",
        "es": "La respuesta del servidor no contiene una lista de modelos.",
        "fr": "La réponse du serveur ne contient pas de liste de modèles.",
        "ja": "サーバーの応答にモデル一覧が含まれていません。",
        "ko": "서버 응답에 모델 목록이 없습니다.",
        "zh-Hans": "服务器响应中不包含模型列表。",
    },
    "This data has been saved, but we could not match an API type for this endpoint. This is usually a mistake. The endpoint should end with /v1/chat/completions, /v1/responses or /v1/messages.": {
        "de": "Die Daten wurden gespeichert, aber für diesen Endpunkt konnte kein API-Typ ermittelt werden. Das ist meist ein Fehler. Der Endpunkt sollte auf /v1/chat/completions, /v1/responses oder /v1/messages enden.",
        "es": "Los datos se han guardado, pero no pudimos determinar un tipo de API para este endpoint. Suele ser un error. El endpoint debería terminar en /v1/chat/completions, /v1/responses o /v1/messages.",
        "fr": "Les données ont été enregistrées, mais aucun type d'API ne correspond à ce point de terminaison. C'est généralement une erreur. Le point de terminaison doit se terminer par /v1/chat/completions, /v1/responses ou /v1/messages.",
        "ja": "データは保存されましたが、このエンドポイントに対応する API タイプを判別できませんでした。通常は入力ミスです。エンドポイントは /v1/chat/completions、/v1/responses、/v1/messages のいずれかで終わる必要があります。",
        "ko": "데이터는 저장되었지만 이 엔드포인트에 맞는 API 유형을 찾지 못했습니다. 대개 입력 오류입니다. 엔드포인트는 /v1/chat/completions, /v1/responses 또는 /v1/messages로 끝나야 합니다.",
        "zh-Hans": "数据已保存，但无法为此端点匹配 API 类型。这通常是填写错误。端点应以 /v1/chat/completions、/v1/responses 或 /v1/messages 结尾。",
    },
    "Unable to encode the request for the Anthropic Messages API.": {
        "de": "Die Anfrage für die Anthropic Messages API konnte nicht kodiert werden.",
        "es": "No se pudo codificar la solicitud para la API Anthropic Messages.",
        "fr": "Impossible d'encoder la requête pour l'API Anthropic Messages.",
        "ja": "Anthropic Messages API 用のリクエストをエンコードできませんでした。",
        "ko": "Anthropic Messages API 요청을 인코딩할 수 없습니다.",
        "zh-Hans": "无法为 Anthropic Messages API 编码请求。",
    },
    "Unknown error.": {
        "de": "Unbekannter Fehler.",
        "es": "Error desconocido.",
        "fr": "Erreur inconnue.",
        "ja": "不明なエラーです。",
        "ko": "알 수 없는 오류입니다.",
        "zh-Hans": "未知错误。",
    },
    "Will be added on save": {
        "de": "Wird beim Speichern hinzugefügt",
        "es": "Se añadirá al guardar",
        "fr": "Sera ajouté à l'enregistrement",
        "ja": "保存時に追加されます",
        "ko": "저장 시 추가됨",
        "zh-Hans": "保存时添加",
    },
    "Will be removed on save": {
        "de": "Wird beim Speichern entfernt",
        "es": "Se eliminará al guardar",
        "fr": "Sera retiré à l'enregistrement",
        "ja": "保存時に削除されます",
        "ko": "저장 시 제거됨",
        "zh-Hans": "保存时移除",
    },
    "%lld models": {
        "de": "%lld Modelle",
        "es": "%lld modelos",
        "fr": "%lld modèles",
        "ja": "%lld 個のモデル",
        "ko": "모델 %lld개",
        "zh-Hans": "%lld 个模型",
    },
    "%lld models selected.": {
        "de": "%lld Modelle ausgewählt.",
        "es": "%lld modelos seleccionados.",
        "fr": "%lld modèles sélectionnés.",
        "ja": "%lld 個のモデルを選択中。",
        "ko": "모델 %lld개 선택됨.",
        "zh-Hans": "已选择 %lld 个模型。",
    },
    "%lld unchecked models will be removed from FlowDown.": {
        "de": "%lld nicht ausgewählte Modelle werden aus FlowDown entfernt.",
        "es": "Se eliminarán de FlowDown %lld modelos desmarcados.",
        "fr": "%lld modèles décochés seront retirés de FlowDown.",
        "ja": "チェックを外した %lld 個のモデルが FlowDown から削除されます。",
        "ko": "선택 해제된 모델 %lld개가 FlowDown에서 제거됩니다.",
        "zh-Hans": "%lld 个未勾选的模型将从 FlowDown 中移除。",
    },
    "Chat Width": {
        "de": "Chatbreite",
        "es": "Ancho del chat",
        "fr": "Largeur du chat",
        "ja": "チャットの幅",
        "ko": "채팅 너비",
        "zh-Hans": "对话宽度",
    },
    "Set how wide messages and the input box may grow in large windows.": {
        "de": "Legt fest, wie breit Nachrichten und das Eingabefeld in großen Fenstern werden dürfen.",
        "es": "Define cuánto pueden ensancharse los mensajes y el cuadro de entrada en ventanas grandes.",
        "fr": "Définit la largeur maximale des messages et de la zone de saisie dans les grandes fenêtres.",
        "ja": "大きなウインドウでメッセージと入力欄をどこまで広げるかを設定します。",
        "ko": "큰 창에서 메시지와 입력란이 넓어질 수 있는 정도를 설정합니다.",
        "zh-Hans": "设置在大窗口中消息与输入框最多能有多宽。",
    },
    "Narrow": {
        "de": "Schmal",
        "es": "Estrecho",
        "fr": "Étroit",
        "ja": "狭い",
        "ko": "좁게",
        "zh-Hans": "窄",
    },
    "Wide": {
        "de": "Breit",
        "es": "Ancho",
        "fr": "Large",
        "ja": "広い",
        "ko": "넓게",
        "zh-Hans": "宽",
    },
    "Full Width": {
        "de": "Volle Breite",
        "es": "Ancho completo",
        "fr": "Pleine largeur",
        "ja": "全幅",
        "ko": "전체 너비",
        "zh-Hans": "铺满",
    },
}

if __name__ == "__main__":
    file_path = sys.argv[1] if len(sys.argv) > 1 else default_file_path()

    data = load_strings(file_path)
    counts = update_missing_translations(
        data,
        new_strings=NEW_STRINGS,
    )
    save_strings(file_path, data)

    print_update_summary(file_path, counts)

# Підписаний IPA для iPhone

Workflow **iOS signed IPA** запускається вручну з `main`. Він збирає Release для iPhoneOS, перевіряє підпис і пакує `Kadr.ipa` для iPhone з iOS 26 або новішою, зареєстрованих у профілі Ad Hoc.

Workflow **iOS device build** автоматично збирає `Kadr-unsigned.ipa` для iPhoneOS після пушу в `main`. Артефакт **Kadr-iOS-Unsigned** можна використати для окремого підпису перед встановленням.

## Налаштування GitHub

У репозиторії Kadr середовище `ios-signing` вже обмежене гілкою `main`. У **Settings → Environments → ios-signing** додай такі secrets.

| GitHub Secret | Значення |
| --- | --- |
| `IOS_DISTRIBUTION_P12_BASE64` | Експортований сертифікат **Apple Distribution** разом із приватним ключем у форматі `.p12`, закодований у Base64. |
| `IOS_DISTRIBUTION_P12_PASSWORD` | Пароль експортованого `.p12`. |
| `IOS_AD_HOC_PROFILE_BASE64` | iOS Ad Hoc `.mobileprovision` у Base64. Профіль має містити відповідний сертифікат, явний App ID і зареєстровані iPhone. Bundle ID береться з профілю. |
| `IOS_IPA_PASSPHRASE` | Випадкова однорядкова парольна фраза завдовжки від 24 символів для шифрування артефакту. |

Конфігурація Apple описана в [інструкції з Ad Hoc підпису](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile/). Оскільки профіль містить ідентифікатори пристроїв, GitHub отримує лише зашифрований артефакт.

## Збірка й завантаження

1. На вкладці **Actions** вибери **iOS signed IPA → Run workflow** на гілці `main`.
2. Завантаж артефакт **Kadr-iOS-Ad-Hoc** і витягни з його ZIP файл `Kadr.ipa.gpg`.
3. Розшифруй через GnuPG, ввівши парольну фразу під час запиту.

   ```bash
   gpg --output Kadr.ipa --decrypt Kadr.ipa.gpg
   ```

4. Встанови `Kadr.ipa` на зареєстрований iPhone через Xcode або Apple Configurator. За потреби ввімкни Developer Mode. [Інструкція Apple](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices/)

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Base64;
import java.util.HexFormat;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;
import javax.crypto.Cipher;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.PBEKeySpec;
import javax.crypto.spec.SecretKeySpec;

// Uses the same JCA and java.util.zip APIs as Android Cost. Fixed inputs are test data only.
class PortableBackupFixture {
    public static void main(String[] args) throws Exception {
        var password = "Cafe\u0301-\u8d26\u672c\ud83d\udd10-portable";
        var salt = HexFormat.of().parseHex("000102030405060708090a0b0c0d0e0f");
        var nonce = HexFormat.of().parseHex("101112131415161718191a1b");
        var key = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
            .generateSecret(new PBEKeySpec(password.toCharArray(), salt, 600_000, 256)).getEncoded();
        var bytes = new ByteArrayOutputStream();
        try (var zip = new ZipOutputStream(bytes)) {
            if (args.length == 0) {
                var entry = new ZipEntry("settings.json");
                entry.setTimeLocal(java.time.LocalDateTime.of(2020, 1, 1, 0, 0));
                zip.putNextEntry(entry);
                zip.write("{}".getBytes(StandardCharsets.UTF_8));
                zip.closeEntry();
            } else {
                var root = Path.of(args[0]);
                for (var name : new String[] {"database.sqlite", "settings.json", "manifest.json"}) {
                    var entry = new ZipEntry(name);
                    entry.setTimeLocal(java.time.LocalDateTime.of(2020, 1, 1, 0, 0));
                    zip.putNextEntry(entry);
                    Files.copy(root.resolve(name), zip);
                    zip.closeEntry();
                }
            }
        }
        var header = new ByteArrayOutputStream();
        header.write("COSTBK01".getBytes(StandardCharsets.US_ASCII));
        header.write(1);
        header.write(salt);
        header.write(nonce);
        var cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(key, "AES"), new GCMParameterSpec(128, nonce));
        cipher.updateAAD(header.toByteArray());
        header.write(cipher.doFinal(bytes.toByteArray()));
        System.out.println("{");
        System.out.println("  \"pbkdf2\": \"" + HexFormat.of().formatHex(key) + "\",");
        System.out.println("  \"backup\": \"" + Base64.getEncoder().encodeToString(header.toByteArray()) + "\"");
        System.out.println("}");
    }
}

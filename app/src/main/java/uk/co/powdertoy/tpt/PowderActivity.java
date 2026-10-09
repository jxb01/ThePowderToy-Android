package uk.co.powdertoy.tpt;

import android.os.Bundle;
import android.view.Display;
import android.view.WindowManager;

import org.libsdl.app.SDLActivity;

import java.io.IOException;
import java.security.KeyStore;
import java.security.KeyStoreException;
import java.security.NoSuchAlgorithmException;
import java.util.Base64;
import java.util.Enumeration;

/**
 * The Powder Toy 的 Android 入口。
 *
 * <p>本体是 SDL2 的 SDLActivity：它会加载 libpowder.so，再回调其中的 SDL_main()。
 * 这里只补三件上游模板没有的小事：
 * <ul>
 *   <li>把系统 CA 证书导出成 PEM 交给 curl，让游戏内 HTTPS 在 Android 上能过校验；</li>
 *   <li>画图时不要自动熄屏；</li>
 *   <li>申请屏幕支持的最高刷新率，降低触摸到出画的延迟。</li>
 * </ul>
 */
public class PowderActivity extends SDLActivity
{
	@Override
	protected void onCreate(Bundle savedInstanceState)
	{
		super.onCreate(savedInstanceState);

		// TPT 是长时间挂着的沙盒：一边画一边看，别让系统把屏幕灭了。
		getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

		requestHighestRefreshRate();
	}

	/**
	 * 让窗口跑在屏幕支持的最高刷新率上。
	 *
	 * <p>模拟本身默认限 60 FPS，但把显示模式顶到 90/120/144 Hz 能实打实降低
	 * 「手指划过去 → 屏幕上出现沙子」的延迟，高刷屏手机上手感差别很直观。
	 * 这里只设置 preferredRefreshRate，由系统挑最接近的显示模式；
	 * 取不到多模式（模拟器、部分设备）就安静地保持默认，不影响功能。
	 */
	private void requestHighestRefreshRate()
	{
		try {
			Display display = getWindowManager().getDefaultDisplay();
			float current = display.getRefreshRate();
			float best = current;
			for (Display.Mode mode : display.getSupportedModes()) {
				if (mode.getRefreshRate() > best) {
					best = mode.getRefreshRate();
				}
			}
			if (best > current + 0.5f) {
				WindowManager.LayoutParams attrs = getWindow().getAttributes();
				attrs.preferredRefreshRate = best;
				getWindow().setAttributes(attrs);
			}
		} catch (Throwable t) {
			// 有的设备/模拟器不给多显示模式，忽略
			t.printStackTrace();
		}
	}

	/** 把 Android 系统信任的根证书打包成 PEM，供原生侧的 libcurl 使用。 */
	public String getCertificateBundle()
	{
		String allPems = "";
		try {
			KeyStore ks = KeyStore.getInstance("AndroidCAStore");
			if (ks != null) {
				ks.load(null, null);
				Enumeration<String> aliases = ks.aliases();
				while (aliases.hasMoreElements()) {
					String alias = (String)aliases.nextElement();
					java.security.cert.X509Certificate cert = (java.security.cert.X509Certificate)ks.getCertificate(alias);
					allPems += "-----BEGIN CERTIFICATE-----\n" + Base64.getMimeEncoder().encodeToString(cert.getEncoded()) + "\n-----END CERTIFICATE-----\n";
				}
			}
		} catch (IOException e) {
			e.printStackTrace();
			return "";
		} catch (KeyStoreException e) {
			e.printStackTrace();
			return "";
		} catch (NoSuchAlgorithmException e) {
			e.printStackTrace();
			return "";
		} catch (java.security.cert.CertificateException e) {
			e.printStackTrace();
			return "";
		}
		return allPems;
	}

	/** 存档要放在应用自己的外部目录里，卸载应用时才会一起清掉。 */
	public String getDefaultDdir()
	{
		return getExternalFilesDir(null).getAbsolutePath();
	}
}

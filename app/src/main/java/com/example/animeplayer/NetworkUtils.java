package com.example.animeplayer;

import android.net.Uri;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.util.ArrayList;
import java.util.List;

public class NetworkUtils {

    /** 搜索某个片源 */
    public static List<VideoItem> search(SourceManager.Source source, String keyword) {
        List<VideoItem> list = new ArrayList<>();
        try {
            String encoded = URLEncoder.encode(keyword, "UTF-8");
            String urlStr = source.api;
            if (urlStr.contains("?")) {
                urlStr += "&wd=" + encoded;
            } else {
                urlStr += "?wd=" + encoded;
            }

            String json = httpGet(urlStr);
            if (json == null) return list;

            JSONObject root = new JSONObject(json);
            JSONArray arr = root.optJSONArray("list");
            if (arr == null) return list;

            for (int i = 0; i < arr.length(); i++) {
                JSONObject obj = arr.getJSONObject(i);
                String title = obj.optString("vod_name", "");
                String vodId = obj.optString("vod_id", "");
                String remarks = obj.optString("vod_remarks", "");
                String pic = obj.optString("vod_pic", "");
                if (!title.isEmpty() && !vodId.isEmpty()) {
                    list.add(new VideoItem(title, vodId,
                                           source.key, source.api, source.name,
                                           remarks, pic));
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return list;
    }

    /** 获取播放地址（详情接口） */
    public static String getPlayUrl(VideoItem item) {
        try {
            String urlStr = item.sourceApi;
            String sep = urlStr.contains("?") ? "&" : "?";
            urlStr += sep + "ac=detail&ids=" + item.vodId;

            String json = httpGet(urlStr);
            if (json == null) return null;

            JSONObject root = new JSONObject(json);
            JSONArray arr = root.optJSONArray("list");
            if (arr == null || arr.length() == 0) return null;

            JSONObject obj = arr.getJSONObject(0);
            String playUrl = obj.optString("vod_play_url", "");
            if (playUrl.isEmpty()) return null;

            // vod_play_url 格式： "第1集$http://xxx.m3u8#第2集$http://yyy.m3u8"
            String[] episodes = playUrl.split("#");
            if (episodes.length > 0) {
                String first = episodes[0];
                int dollar = first.indexOf('$');
                if (dollar > 0) {
                    return first.substring(dollar + 1);
                }
                return first;
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return null;
    }

    /** 基础HTTP GET */
    private static String httpGet(String urlStr) {
        HttpURLConnection conn = null;
        BufferedReader reader = null;
        try {
            URL url = new URL(urlStr);
            conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("GET");
            conn.setConnectTimeout(10000);
            conn.setReadTimeout(15000);
            conn.setRequestProperty("User-Agent",
                                    "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36");

            if (conn.getResponseCode() != HttpURLConnection.HTTP_OK) {
                return null;
            }

            InputStream in = conn.getInputStream();
            reader = new BufferedReader(new InputStreamReader(in, "UTF-8"));
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line);
            }
            return sb.toString();
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        } finally {
            try { if (reader != null) reader.close(); } catch (Exception ignored) {}
            if (conn != null) conn.disconnect();
        }
    }
}

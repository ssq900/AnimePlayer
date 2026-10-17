package com.example.animeplayer;

import android.content.Context;
import android.content.SharedPreferences;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.List;

public class SourceManager {

    public static class Source {
        public String name;
        public String api;
        public String key;

        public Source(String name, String api, String key) {
            this.name = name;
            this.api = api;
            this.key = key;
        }
    }

    private static final String PREF_NAME = "source_prefs";
    private static final String KEY_SOURCES = "sources_json";
    private SharedPreferences prefs;

    public SourceManager(Context context) {
        prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
    }

    /** 保存片源列表（用户粘贴JSON后调用） */
    public void saveSourcesFromJson(String jsonStr) {
        prefs.edit().putString(KEY_SOURCES, jsonStr).apply();
    }

    /** 读取所有片源 */
    public List<Source> getSources() {
        List<Source> list = new ArrayList<>();
        String json = prefs.getString(KEY_SOURCES, "");
        if (json.isEmpty()) return list;
        try {
            JSONObject root = new JSONObject(json);
            JSONArray sites = root.optJSONArray("sites");
            if (sites == null) return list;
            for (int i = 0; i < sites.length(); i++) {
                JSONObject site = sites.getJSONObject(i);
                String name = site.optString("name", "未知源");
                String api = site.optString("api", "");
                String key = site.optString("key", "");
                if (!api.isEmpty()) {
                    list.add(new Source(name, api, key));
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return list;
    }

    /** 搜索：遍历所有片源，返回结果 */
    public List<VideoItem> searchAll(String keyword) {
        List<VideoItem> results = new ArrayList<>();
        for (Source s : getSources()) {
            List<VideoItem> r = NetworkUtils.search(s, keyword);
            results.addAll(r);
        }
        return results;
    }
}

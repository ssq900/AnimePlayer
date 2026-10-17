package com.example.animeplayer;

import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import java.util.ArrayList;
import java.util.List;

public class MainActivity extends AppCompatActivity {

    private EditText etSearch;
    private Button btnSearch;
    private TextView tvStatus;
    private RecyclerView recyclerView;
    private ListAdapter adapter;
    private List<VideoItem> results = new ArrayList<>();
    private SourceManager sourceManager;
    private Handler mainHandler = new Handler(Looper.getMainLooper());

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        sourceManager = new SourceManager(this);

        etSearch = findViewById(R.id.etSearch);
        btnSearch = findViewById(R.id.btnSearch);
        tvStatus = findViewById(R.id.tvStatus);
        recyclerView = findViewById(R.id.recyclerView);

        recyclerView.setLayoutManager(new LinearLayoutManager(this));
        adapter = new ListAdapter(this, results, new ListAdapter.OnItemClick() {
                @Override
                public void onClick(VideoItem item) {
                    openVideo(item);
                }
            });
        recyclerView.setAdapter(adapter);

        btnSearch.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    doSearch();
                }
            });

        // 首次打开：检查片源，没有则提示导入
        if (sourceManager.getSources().isEmpty()) {
            showImportDialog();
        } else {
            updateStatus();
        }
    }

    /** 弹出片源导入对话框 */
    private void showImportDialog() {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("导入片源");
        builder.setMessage("请粘贴片源JSON（TVBox格式）");

        final EditText input = new EditText(this);
        input.setHint("{\"sites\":[{\"name\":\"...\",\"api\":\"...\"}]}");
        input.setMinLines(6);
        input.setTextColor(0xFFFFFFFF);
        input.setHintTextColor(0xFF888888);
        builder.setView(input);

        builder.setPositiveButton("导入", new DialogInterface.OnClickListener() {
                @Override
                public void onClick(DialogInterface dialog, int which) {
                    String json = input.getText().toString().trim();
                    if (json.isEmpty()) {
                        Toast.makeText(MainActivity.this, "内容不能为空", Toast.LENGTH_SHORT).show();
                        return;
                    }
                    try {
                        sourceManager.saveSourcesFromJson(json);
                        updateStatus();
                        Toast.makeText(MainActivity.this, "片源导入成功", Toast.LENGTH_SHORT).show();
                    } catch (Exception e) {
                        Toast.makeText(MainActivity.this, "JSON格式错误", Toast.LENGTH_SHORT).show();
                    }
                }
            });

        builder.setNegativeButton("取消", null);
        builder.setNeutralButton("查看已有源", new DialogInterface.OnClickListener() {
                @Override
                public void onClick(DialogInterface dialog, int which) {
                    List<SourceManager.Source> list = sourceManager.getSources();
                    StringBuilder sb = new StringBuilder();
                    for (SourceManager.Source s : list) {
                        sb.append("· ").append(s.name).append("\n");
                    }
                    new AlertDialog.Builder(MainActivity.this)
                        .setTitle("已导入片源 (" + list.size() + "个)")
                        .setMessage(sb.length() == 0 ? "暂无片源" : sb.toString())
                        .setPositiveButton("确定", null)
                        .show();
                }
            });

        builder.show();
    }

    private void updateStatus() {
        int count = sourceManager.getSources().size();
        if (count == 0) {
            tvStatus.setText("未导入片源");
            tvStatus.setTextColor(0xFFFF6B6B);
        } else {
            tvStatus.setText("已加载 " + count + " 个片源");
            tvStatus.setTextColor(0xFF6BCB77);
        }
    }

    private void doSearch() {
        final String keyword = etSearch.getText().toString().trim();
        if (keyword.isEmpty()) {
            Toast.makeText(this, "请输入搜索关键词", Toast.LENGTH_SHORT).show();
            return;
        }
        if (sourceManager.getSources().isEmpty()) {
            showImportDialog();
            return;
        }

        tvStatus.setText("搜索中...");
        tvStatus.setTextColor(0xFFFFD93D);

        new Thread(new Runnable() {
                @Override
                public void run() {
                    final List<VideoItem> list = sourceManager.searchAll(keyword);
                    mainHandler.post(new Runnable() {
                            @Override
                            public void run() {
                                results.clear();
                                results.addAll(list);
                                adapter.notifyDataSetChanged();
                                if (list.isEmpty()) {
                                    tvStatus.setText("未找到结果");
                                    tvStatus.setTextColor(0xFFFF6B6B);
                                } else {
                                    tvStatus.setText("找到 " + list.size() + " 个结果");
                                    tvStatus.setTextColor(0xFF6BCB77);
                                }
                            }
                        });
                }
            }).start();
    }

    private void openVideo(final VideoItem item) {
        tvStatus.setText("解析播放地址...");
        tvStatus.setTextColor(0xFFFFD93D);

        new Thread(new Runnable() {
                @Override
                public void run() {
                    final String playUrl = NetworkUtils.getPlayUrl(item);
                    mainHandler.post(new Runnable() {
                            @Override
                            public void run() {
                                if (playUrl == null || playUrl.isEmpty()) {
                                    tvStatus.setText("播放地址解析失败");
                                    tvStatus.setTextColor(0xFFFF6B6B);
                                    Toast.makeText(MainActivity.this,
                                                   "该片源无法解析播放地址", Toast.LENGTH_SHORT).show();
                                    return;
                                }
                                tvStatus.setText("已加载 " + sourceManager.getSources().size() + " 个片源");
                                tvStatus.setTextColor(0xFF6BCB77);

                                Intent intent = new Intent(MainActivity.this, VideoActivity.class);
                                intent.putExtra("url", playUrl);
                                intent.putExtra("title", item.title);
                                startActivity(intent);
                            }
                        });
                }
            }).start();
    }
}

package com.example.animeplayer;

import android.app.Activity;
import android.net.Uri;
import android.os.Bundle;
import android.view.WindowManager;
import android.widget.MediaController;
import android.widget.TextView;
import android.widget.VideoView;

public class VideoActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // 全屏播放
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN,
                             WindowManager.LayoutParams.FLAG_FULLSCREEN);
        setContentView(R.layout.activity_video);

        VideoView videoView = findViewById(R.id.videoView);
        TextView tvTitle = findViewById(R.id.tvVideoTitle);

        String url = getIntent().getStringExtra("url");
        String title = getIntent().getStringExtra("title");
        tvTitle.setText(title != null ? title : "播放中");

        if (url != null && !url.isEmpty()) {
            MediaController controller = new MediaController(this);
            controller.setAnchorView(videoView);
            videoView.setMediaController(controller);
            videoView.setVideoURI(Uri.parse(url));
            videoView.start();
        }
    }
}

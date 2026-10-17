package com.example.animeplayer;

public class VideoItem {
    public String title;
    public String vodId;
    public String sourceKey;
    public String sourceApi;
    public String sourceName;
    public String remarks;
    public String pic;

    public VideoItem(String title, String vodId, String sourceKey,
                     String sourceApi, String sourceName,
                     String remarks, String pic) {
        this.title = title;
        this.vodId = vodId;
        this.sourceKey = sourceKey;
        this.sourceApi = sourceApi;
        this.sourceName = sourceName;
        this.remarks = remarks;
        this.pic = pic;
    }

    @Override
    public String toString() {
        return title + (remarks.isEmpty() ? "" : "  ·  " + remarks);
    }
}

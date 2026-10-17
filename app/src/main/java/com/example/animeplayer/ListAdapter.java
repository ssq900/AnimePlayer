package com.example.animeplayer;

import android.content.Context;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import java.util.List;

public class ListAdapter extends RecyclerView.Adapter<ListAdapter.VH> {

    public interface OnItemClick {
        void onClick(VideoItem item);
    }

    private final Context context;
    private final List<VideoItem> data;
    private final OnItemClick listener;

    public ListAdapter(Context context, List<VideoItem> data, OnItemClick listener) {
        this.context = context;
        this.data = data;
        this.listener = listener;
    }

    @NonNull
    @Override
    public VH onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View v = LayoutInflater.from(context)
            .inflate(R.layout.list_item, parent, false);
        return new VH(v);
    }

    @Override
    public void onBindViewHolder(@NonNull VH holder, int position) {
        final VideoItem item = data.get(position);
        holder.tvTitle.setText(item.title);
        holder.tvInfo.setText("来源: " + item.sourceName
                              + (item.remarks.isEmpty() ? "" : "  |  " + item.remarks));
        holder.itemView.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    if (listener != null) listener.onClick(item);
                }
            });
    }

    @Override
    public int getItemCount() { return data.size(); }

    static class VH extends RecyclerView.ViewHolder {
        TextView tvTitle, tvInfo;
        VH(View v) {
            super(v);
            tvTitle = v.findViewById(R.id.tvTitle);
            tvInfo = v.findViewById(R.id.tvInfo);
        }
    }
}

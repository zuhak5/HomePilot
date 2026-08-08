package com.homepilot.app

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.widget.ImageView
import android.widget.TextView
import android.graphics.Color
import com.google.android.gms.ads.nativead.AdChoicesView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.NativeAdFactory

class HomePilotNativeAdFactory(
    private val context: Context,
) : NativeAdFactory {
    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?,
    ): NativeAdView {
        val view = LayoutInflater.from(context)
            .inflate(R.layout.homepilot_native_ad, null) as NativeAdView
        val icon = view.findViewById<ImageView>(R.id.homepilot_ad_icon)
        val headline = view.findViewById<TextView>(R.id.homepilot_ad_headline)
        val body = view.findViewById<TextView>(R.id.homepilot_ad_body)
        val advertiser = view.findViewById<TextView>(R.id.homepilot_ad_advertiser)
        val callToAction = view.findViewById<TextView>(R.id.homepilot_ad_cta)
        val adChoices = view.findViewById<AdChoicesView>(R.id.homepilot_ad_choices)

        view.iconView = icon
        view.headlineView = headline
        view.bodyView = body
        view.advertiserView = advertiser
        view.callToActionView = callToAction
        if (adChoices != null) {
            view.adChoicesView = adChoices
        }

        val backgroundColorStr = customOptions?.get("backgroundColor") as? String
        val textColorStr = customOptions?.get("textColor") as? String
        if (!backgroundColorStr.isNullOrEmpty()) {
            try {
                view.setBackgroundColor(Color.parseColor(backgroundColorStr))
            } catch (_: Exception) {}
        }
        if (!textColorStr.isNullOrEmpty()) {
            try {
                val color = Color.parseColor(textColorStr)
                headline.setTextColor(color)
                body.setTextColor(color)
            } catch (_: Exception) {}
        }

        headline.text = nativeAd.headline
        body.text = nativeAd.body
        body.visibility = if (nativeAd.body.isNullOrBlank()) View.GONE else View.VISIBLE
        advertiser.text = nativeAd.advertiser
        advertiser.visibility =
            if (nativeAd.advertiser.isNullOrBlank()) View.GONE else View.VISIBLE
        callToAction.text = nativeAd.callToAction
        callToAction.visibility =
            if (nativeAd.callToAction.isNullOrBlank()) View.INVISIBLE else View.VISIBLE
        val drawable = nativeAd.icon?.drawable
        if (drawable == null) {
            icon.visibility = View.GONE
        } else {
            icon.setImageDrawable(drawable)
            icon.visibility = View.VISIBLE
        }

        view.setNativeAd(nativeAd)
        return view
    }
}

# HCI Time Management app
This is the GitHub repository for the code of the time management app developed by the **24/7-ish** group as part of the HCI course in ACSAI, Sapienza University, a.y. 2025–2026.

### Group members

* Inga Grigoryan- @Inga-1
* Armen Grigoryan- @ArmenGrigoryan112
* Maria Zakaryan-@zakaryan-jpg
* Louisa Korshunova- @LouisaKorshunova

### Description of the app

This is a time management app made for Apple iPhones operating on iOS. It organizes the user’s daily schedule based on their energy levels, dynamically modifying the schedule as the day progresses and tasks get completed. Internally, the app adapts task planning according to the user’s available time, priorities, and reported energy, helping them manage their day in a more flexible and personalized way.

As for the **technical aspect** of the app, Enersync is built with **Swift** and **SwiftUI**. It uses a simple **MVVM-style structure**, with local data models, one main task manager, and reusable SwiftUI views. Tasks are stored locally using **UserDefaults** and `Codable`, so the app works fully on-device with no account, server, or internet connection.

EnerSync includes a lightweight on-device classification system using Apple’s native and already integrated **NaturalLanguage** framework to estimate whether tasks are draining or restorative. Based on this, the app updates the user’s energy level, reorders tasks, suggests better time slots, and supports local reminders through iOS notifications.
 
